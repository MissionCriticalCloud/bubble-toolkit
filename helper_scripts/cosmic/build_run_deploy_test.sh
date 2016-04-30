#!/bin/bash

# This script builds and runs Cosmic and deploys a data center using the supplied Marvin config.
# When KVM is used, RPMs are built and installed on the hypervisor.
# When done, it runs the desired tests.

# Source the helper functions and
. `dirname $0`/helperlib.sh


function usage {
  printf "Usage: %s: -m marvinCfg [ -s <skip compile> -t <run tests> -T <mvn -T flag> ]\n" $(basename $0) >&2
}

# Options
skip=0
run_tests=0
compile_threads=
while getopts 'm:T:st' OPTION
do
  case $OPTION in
  m)    marvinCfg="$OPTARG"
        ;;
  s)    skip=1
        ;;
  t)    run_tests=1
        ;;
  T)    compile_threads="-T $OPTARG"
        ;;
  esac
done

echo "Received arguments:"
echo "skip = ${skip}"
echo "run_tests = ${run_tests}"
echo "marvinCfg = ${marvinCfg}"
echo "compile_threads = ${compile_threads}"

# Check if a marvin dc file was specified
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  usage
  exit 1
else
  echo "Using Marvin config '${marvinCfg}'."
fi

if [ ! -f "${marvinCfg}" ]; then
    echo "Supplied Marvin config not found!"
    exit 1
fi

echo "Started!"
date

# Find ip
host_ip=`ip addr | grep 'inet 192' | cut -d: -f2 | awk '{ print $2 }' | awk -F\/24 '{ print $1 }'`

COSMIC_BUILD_PATH=/data/git/$HOSTNAME/cosmic
COSMIC_CORE_PATH=$COSMIC_BUILD_PATH/cosmic-core
PACKAGING_BUILD_PATH=/data/git/$HOSTNAME/packaging

# We work from here
cd $COSMIC_BUILD_PATH

if [ $? -gt 0  ]; then
  echo "ERROR: git repo not found!"
  exit 1
fi

echo "OK"

# Parse marvin config
parse_marvin_config ${marvinCfg}

# Create storage paths
mkdir -p ${primarystorage}
mkdir -p ${secondarystorage}

killall -9 java
while timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for socket to close.."; sleep 10; done

# Cleanup UI cached items
find /data/git/$HOSTNAME/cosmic/cosmic-client -name \*.gz | xargs rm -f

# Config nexus for maven
config_maven

# Short pre-compile may be needed to solve dependency
mvn clean install -N

# Compile Cosmic
if [ ${skip} -eq 0 ]; then
  # Compile Cosmic
  cd "$COSMIC_BUILD_PATH"
  echo "Compiling Cosmic"
  date
  mvn clean install -P developer,systemvm ${compile_threads}
  if [ $? -ne 0 ]; then
    date
    echo "Build failed, please investigate!"
    exit 1
  fi
  date

  # Compile RPM packages for KVM hypervisor
  # When something VR related is changed, one must use the RPMs from the branch we're testing
  if [[ "$hypervisor" == "kvm" ]]; then
    echo "Creating rpm packages for ${hypervisor}"
    date
    cd $PACKAGING_BUILD_PATH

    # Clean up better
    rm -rf dist/rpmbuild/RPMS/
    # CentOS7 is hardcoded for now
    ./package_cosmic.sh -d centos7 -f ${COSMIC_BUILD_PATH}
    if [ $? -ne 0 ]; then
      date
      echo "RPM build failed, please investigate!"
      exit 1
    fi

    # Push to hypervisor
    install_kvm_packages ${hvip1} ${hvuser1} ${hvpass1}
    date

    # Do we have a second hypervisor
    if [ ! -z  ${hvip2} ]; then
      # Push to hypervisor
      install_kvm_packages ${hvip2} ${hvuser2} ${hvpass2}
    fi

  else
    echo "No RPM packages needed for ${hypervisor}"
  fi

fi

# Cleaning Hypervisor
echo "Cleaning hypervisor"
if [[ "$hypervisor" == "kvm" ]]; then
    clean_kvm ${hvip1} ${hvuser1} ${hvpass1}

    # Do we have a second hypervisor
    if [ ! -z  ${hvip2} ]; then
      clean_kvm ${hvip2} ${hvuser2} ${hvpass2}
    fi
elif [[ "$hypervisor" == "xenserver" ]]; then
    clean_xenserver ${hvip1} ${hvuser1} ${hvpass1}

    # Do we have a second hypervisor
    if [ ! -z  ${hvip2} ]; then
      # Push to hypervisor
      clean_xenserver ${hvip2} ${hvuser2} ${hvpass2}
    fi
fi

cd "$COSMIC_CORE_PATH"

# Install Marvin
echo "Installing Marvin"
pip install --upgrade "https://beta-nexus.mcc.schubergphilis.com/service/local/artifact/maven/redirect?r=snapshots&g=cloud.cosmic&a=cloud-marvin&v=LATEST&p=tar.gz" --allow-external mysql-connector-python

# Deploy DB
echo "Deploying Cosmic DB"
mvn -P developer -pl developer -Ddeploydb -T 4
if [ $? -ne 0 ]; then
  date
  echo "Build failed, please investigate!"
  exit 1
fi
date

# Configure the hostname properly - it doesn't exist if the deployeDB doesn't include devcloud
# Insert OVS bridge
# Garbage collector
# Adding the right SystemVMs, for both KVM and XenServer
# Adding the tiny linux VM templates for KVM and XenServer
# Make service offering support HA
cloud_conf_cosmic

# Run the Cosmic management server
echo "Double checking Cosmic is not already running"
killall -9 java
while timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for socket to close.."; sleep 10; done

# Start Cosmic Management Server
cd $COSMIC_BUILD_PATH/cosmic-client
echo "Starting Cosmic (debug mode)"
#mvnDebug sets suspend=y and waits for connection
#mvnDebug -pl :cloud-client-ui jetty:run > jetty.log 2>&1 &
/usr/lib/jvm/java/bin/java -Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000 -classpath /usr/share/maven/boot/plexus-classworlds.jar -Dclassworlds.conf=/usr/share/maven/bin/m2.conf -Dmaven.home=/usr/share/maven org.codehaus.plexus.classworlds.launcher.Launcher -pl :cloud-client-ui jetty:run > jetty.log 2>&1 &

# Wait until it comes up
echo "Waiting for Cosmic to start"
while ! timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for Mgt server to start.."; sleep 10; done

# Systemvm template for hypervisor type
if [[ "${hypervisor}" == "kvm" ]]; then
  systemtemplate="/data/templates/cosmic-systemvm.qcow2"
  imagetype="qcow2"
 elif [[ "${hypervisor}" == "xenserver" ]]; then
  systemtemplate="/data/templates/cosmic-systemvm.vhd"
  imagetype="vhd"
fi

echo "Install systemvm template.."
# Consider using -f and point to local cached file
date
bash -x $COSMIC_CORE_PATH/scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondarystorage} -f ${systemtemplate} -h ${hypervisor} -o localhost -r root -e ${imagetype} -F
date

echo "Deploy data center.."
python -m marvin.deployDataCenter -i ${marvinCfg}
if [ $? -ne 0 ]; then
  date
  echo "Deployment failed, please investigate!"
  exit 1
fi

# Wait until templates are ready
date
echo "Checking template status.."
python /data/shared/helper_scripts/cosmic/wait_template_ready.py
date

# Run the tests
if [ ${run_tests} -eq 1 ]; then
  echo "Running Marvin tests.."
  bash -x /data/shared/helper_scripts/cosmic/run_marvin_router_tests.sh ${marvinCfg}
else
  echo "Not running tests (use -t flag to run them)"
fi

echo "Finished"
date
