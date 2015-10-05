#!/bin/bash

# This script builds and runs Apache CloudStack and deploys a data center using the supplied Marvin config.
# When KVM is used, RPMs are built and installed on the hypervisor.
# When done, it runs the desired tests.

function usage {
  printf "Usage: %s: -m marvinCfg [ -s <skip compile> -t <run tests> ]\n" $(basename $0) >&2
}

# Options
skip=0
run_tests=0
while getopts 'm:st' OPTION
do
  case $OPTION in
  m)    marvinCfg="$OPTARG"
        ;;
  s)    skip=1
        ;;
  t)    run_tests=1
        ;;
  esac
done

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

echo "Received arguments:"
echo "skip = ${skip}"
echo "run_tests = ${run_tests}"
echo "marvinCfg = ${marvinCfg}"

echo "Started!"
date

# Find ip
host_ip=`ip addr | grep 'inet 192' | cut -d: -f2 | awk '{ print $2 }' | awk -F\/24 '{ print $1 }'`

# We work from here
cd /data/git/$HOSTNAME/cloudstack

if [ $? -gt 0  ]; then
  echo "ERROR: git repo not found!"
  exit 1
fi

echo "OK"

# Parse marvin config
# This should be done in python instead,
# for now we just hack the common usecase together

# All we support is a single cluster with 1 or 2 hypervisors.

# We grab some useful info from the supplied Marvin json file.

# Zone name
zone=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['name']
")

# Hypervisor type
hypervisor=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hypervisor'].lower()
")

# Primary storage location
primarystorage=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['primaryStorages'][0]['url']" | cut -d: -f3
)
mkdir -p ${primarystorage}

secondarystorage=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['secondaryStorages'][0]['url']" | cut -d: -f3
)
mkdir -p ${secondarystorage}

# username hypervisor 1
hvuser1=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][0]['username']
except:
 print ''
")

# password hypervisor 1
hvpass1=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][0]['password']
except:
 print ''
")

# ip adress hypervisor 1
hvip1=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][0]['url']
except:
 print ''
" | cut -d/ -f3)

# username hypervisor 2
hvuser2=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][1]['username']
except:
 print ''
")

# password hypervisor 2
hvpass2=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][1]['password']
except:
 print ''
")

# ip adress hypervisor 2
hvip2=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][1]['url']
except:
 print ''
" | cut -d/ -f3)

# Install CloudStack packages to KVM
function install_kvm_packages {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # scp packages to hypervisor, remove existing, then install new ones
  ${ssh_base} ${hvuser}@${hvip} rm cloudstack-*
  ${scp_base} ../dist/rpmbuild/RPMS/x86_64/* ${hvuser}@${hvip}:
  ${ssh_base} ${hvuser}@${hvip} yum -y remove cloudstack-common
  ${ssh_base} ${hvuser}@${hvip} rm -f /etc/cloudstack/agent/agent.properties
  ${ssh_base} ${hvuser}@${hvip} yum -y localinstall cloudstack-agent* cloudstack-common*
}

function clean_kvm {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # Clean KVM in case it has been used before
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload
  ${ssh_base} ${hvuser}@${hvip} systemctl stop cloudstack-agent
  ${ssh_base} ${hvuser}@${hvip} systemctl disable cloudstack-agent
  ${ssh_base} ${hvuser}@${hvip} systemctl restart libvirtd
  ${ssh_base} ${hvuser}@${hvip} "for host in \$(virsh list | awk '{print \$2;}' | grep -v Name |egrep -v '^\$'); do virsh destroy \$host; done"
}

function clean_xenserver {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  /data/shared/helper_scripts/cleaning/xapi_cleanup_xenservers.py http://${hvip} ${hvuser} ${hvpass}

}

# Compile CloudStack
if [ ${skip} -eq 0 ]; then

  # Stop previous mgt server
  killall -9 java
  while timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for socket to close.."; sleep 10; done

  # Compile RPM packages for KVM hypervisor
  # When something VR related is changed, one must use the RPMs from the branch we're testing
  if [[ "$hypervisor" == "kvm" ]]; then
    echo "Creating rpm packages for ${hypervisor}"
    date
    cd packaging

    # Use 4 cores when compiling ACS
    sed -i '/mvn -Psystemvm -DskipTests/c\mvn -Psystemvm -DskipTests $FLAGS clean package -T 4' /data/git/${HOSTNAME}/cloudstack/packaging/centos7/cloud.spec

    # CentOS7 is hardcoded for now
    ./package.sh -d centos7

    # Done, put it back
    git reset --hard

    # Push to hypervisor
    install_kvm_packages ${hvip1} ${hvuser1} ${hvpass1}
    date

    # Do we have a second hypervisor
    if [ ! -z  ${hvip2} ]; then
      # Push to hypervisor
      install_kvm_packages ${hvip2} ${hvuser2} ${hvpass2}
    fi

    # We do not need to clean the next compile
    clean=""
  else
    echo "No RPM packages needed for ${hypervisor}"

    # We use clean here since we didn't compile rpms
    clean="clean"
  fi

  # cloudstack compile
  cd /data/git/$HOSTNAME/cloudstack
  echo "Compiling CloudStack"
  date
  mvn ${clean} install -P developer,systemvm -DskipTests -T 4
  date
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

# Deploy DB
echo "Deploying CloudStack DB"
mvn -P developer -pl developer -Ddeploydb -T 4
date

# Configure the hostname properly - it doesn't exist if the deployeDB doesn't include devcloud
mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '$host_ip') ON DUPLICATE KEY UPDATE value = '$host_ip';"
# Insert OVS bridge
mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'sdn.ovs.controller.default.label', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"

# Adding the right SystemVMs, for both KVM and XenServer
# Adding the tiny linux VM templates for KVM and XenServer
echo "Config Templates"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-xen.vhd.bz2' where id=1;"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2' where id=3;"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-kvm.qcow2.bz2', guest_os_id=140, name='tiny linux kvm', display_text='tiny linux kvm', hvm=1 where id=4;"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2', guest_os_id=140, name='tiny linux xenserver', display_text='tiny linux xenserver', hvm=1 where id=2;"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2', guest_os_id=140, name='tiny linux xenserver', display_text='tiny linux xenserver', hvm=1 where id=5;"

# Make service offering support HA
echo "Set all offerings to HA"
mysql -u cloud -pcloud cloud --exec "UPDATE service_offering SET ha_enabled = 1;"
mysql -u cloud -pcloud cloud --exec "UPDATE vm_instance SET ha_enabled = 1;"

# Install Marvin
echo "Installing Marvin"
pip install --upgrade tools/marvin/dist/Marvin-*.tar.gz --allow-external mysql-connector-python

# Run the CloudStack management server
echo "Double checking CloudStack is not already running"
killall -9 java
while timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for socket to close.."; sleep 10; done

echo "Starting CloudStack"
mvn -pl :cloud-client-ui jetty:run > jetty.log 2>&1 &

# Wait until it comes up
echo "Waiting for CloudStack to start"
while ! timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do echo "Waiting for Mgt server to start.."; sleep 10; done

# Systemvm template for hypervisor type
if [[ "${hypervisor}" == "kvm" ]]; then
  systemtemplate="/data/templates/systemvm64template-master-4.6.0-kvm.qcow2"
  imagetype="qcow2"
 elif [[ "${hypervisor}" == "xenserver" ]]; then
  systemtemplate="/data/templates/systemvm64template-master-4.6.0-xen.vhd"
  imagetype="vhd"
fi 

echo "Install systemvm template.."
# Consider using -f and point to local cached file
date
bash -x ./scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondarystorage} -f ${systemtemplate} -h ${hypervisor} -o localhost -r root -e ${imagetype} -F
date

echo "Deploy data center.."
python /data/git/$HOSTNAME/cloudstack/tools/marvin/marvin/deployDataCenter.py -i ${marvinCfg}
date

# Wait until templates are ready
echo "Checking template status.."
bash -x /data/shared/helper_scripts/cloudstack/wait_template_ready.sh
date

# Run the tests
if [ ${run_tests} -eq 1 ]; then
  echo "Running Marvin tests.."
  bash -x /data/shared/helper_scripts/cloudstack/run_marvin_router_tests.sh ${marvinCfg}
else
  echo "Not running tests (use -t flag to run them)"
fi

echo "Finished"
date
