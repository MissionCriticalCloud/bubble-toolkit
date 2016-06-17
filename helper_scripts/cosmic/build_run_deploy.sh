#!/bin/bash

# This script builds and runs Cosmic and deploys a data center using the supplied Marvin config.
# When KVM is used, RPMs are built and installed on the hypervisor.

# As building is now done locally, packages which were installed in CS1
# now need to be installed "locally":
#
# yum -y install maven tomcat mkisofs python-paramiko jakarta-commons-daemon-jsvc jsvc ws-commons-util genisoimage gcc python MySQL-python openssh-clients wget git python-ecdsa bzip2 python-setuptools mariadb-server mariadb python-devel vim nfs-utils screen setroubleshoot openssh-askpass java-1.8.0-openjdk-devel.x86_64 rpm-build rubygems nc libffi-devel openssl-devel
# yum -y install http://mirror.karneval.cz/pub/linux/fedora/epel/epel-release-latest-7.noarch.rpm
# yum --enablerepo=epel -y install sshpass mariadb mysql-connector-python
# yum -y install nmap
#
# If agreed, this needs to be moved to the bubble-cookbook
#

# Source the helper functions
. `dirname $0`/helperlib.sh


function maven_build {
  build_dir=$1
  compile_threads=$2
  disable_maven_clean=$3
  # Compile Cosmic
  cwd=$(pwd)
  cd "${build_dir}"
  echo "Compiling Cosmic"
  date
  maven_unit_tests=""
  if [ "${disable_maven_unit_tests}" = "1" ]; then
    maven_unit_tests=" -DskipTests "
  fi
  maven_clean="clean"
  if [ "${disable_maven_clean}" = "1" ]; then
    maven_clean=""
  fi

  echo mvn ${maven_clean} install -P developer,systemvm,sonar-ci-cosmic ${compile_threads} -Dcosmic.dir=${build_dir} ${maven_unit_tests}
  # JENKINS: mavenBuild: maven job with goals: clean install deploy -U -Pdeveloper -Psystemvm -Psonar-ci-cosmic -Dcosmic.dir=\"${injectJobVariable(CUSTOM_WORKSPACE_PARAM)}\"
  # Leaving out deploy and -U (Forces a check for updated releases and snapshots on remote repositories)
  mvn ${maven_clean} install -P developer,systemvm,sonar-ci-cosmic ${compile_threads} -Dcosmic.dir=${build_dir} ${maven_unit_tests}
  if [ $? -ne 0 ]; then
    date
    echo "Build failed, please investigate!"
    exit 1
  fi
  cd "${pwd}"
  date
}

function rpm_package {
  PACKAGING_BUILD_PATH=$1
  COSMIC_BUILD_PATH=$2
  cwd=$(pwd)
  date
  cd "$1"

  # Clean up better
  rm -rf dist
  # remove possible leftover from build script
  [ -h ../cosmic/cosmic ] && rm ../cosmic/cosmic
  [ -h ../cosmic-*-SNAPSHOT ] && rm ../cosmic-*-SNAPSHOT

  # CentOS7 is hardcoded for now
  # JENKINS: packageCosmicJob: same
  ./package_cosmic.sh -d centos7 -f ${COSMIC_BUILD_PATH}
  if [ $? -ne 0 ]; then
    date
    echo "RPM build failed, please investigate!"
    exit 1
  fi
  cd "${pwd}"
}

# deploy_cloudstack_war should be sourced from ci-deploy-infra.sh, but contains executing code
# so should be moved to a "library" sh script which can be sourced
function deploy_cloudstack_war {
  local csip=$1
  local csuser=$2
  local cspass=$3
  local dbscripts_dir="$4"
  local war_file="$5"

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  ${ssh_base} ${csuser}@${csip} mkdir -p ~tomcat/db
  ${scp_base} ${dbscripts_dir} ${csuser}@${csip}:~tomcat/db/
  ${scp_base} ${war_file} ${csuser}@${csip}:~tomcat/webapps/client.war
  ${ssh_base} ${csuser}@${csip} service tomcat start
}
# If this Jenkins-like build_run_deploy script is aproved, move function below to library script file
function undeploy_cloudstack_war {
  local csip=$1
  local csuser=$2
  local cspass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  ${ssh_base} ${csuser}@${csip} service tomcat stop
  ${ssh_base} ${csuser}@${csip} rm -rf ~tomcat/db
  ${ssh_base} ${csuser}@${csip} rm -rf ~tomcat/webapps/client*
}

function enable_remote_debug_war {
  local csip=$1
  local csuser=$2
  local cspass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  ${ssh_base} ${csuser}@${csip}  'if ! grep -q CATALINA_OPTS /etc/tomcat/tomcat.conf; then echo '\''CATALINA_OPTS="-agentlib:jdwp=transport=dt_socket,address=8000,server=y,suspend=n"'\'' >> /etc/tomcat/tomcat.conf; echo Configuring DEBUG access for management server; sleep 10; service tomcat stop; service tomcat start; fi'
}
function enable_remote_debug_kvm {
  local csip=$1
  local csuser=$2
  local cspass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  ${ssh_base} ${csuser}@${csip}  'if [ ! -f /etc/systemd/system/cosmic-agent.service.d/debug.conf ]; then echo Configuring DEBUG access for KVM server; mkdir -p /etc/systemd/system/cosmic-agent.service.d/; printf "[Service]\nEnvironment=JAVA_REMOTE_DEBUG=-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000" > /etc/systemd/system/cosmic-agent.service.d/debug.conf; systemctl daemon-reload; fi'
}
function cleanup_cs {
  local csip=$1
  local csuser=$2
  local cspass=$3

  undeploy_cloudstack_war ${csip} ${csuser} ${cspass}
  # Clean DB in case of a re-deploy. Should be done with the sql scripts, apparently doesnt work
  mysql -h ${csip} -u root -e "DROP DATABASE IF EXISTS \`billing\`;" >/dev/null
  mysql -h ${csip} -u root -e "DROP DATABASE IF EXISTS \`cloud\`;" >/dev/null
  mysql -h ${csip} -u root -e "DROP DATABASE IF EXISTS \`cloud_usage\`;" >/dev/null
}
function cleanup_kvm {
  local hvip=$1
  local hvuser=$2
  local hvpass=$3

  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  # Remove Cosmic agent
  ${ssh_base} ${hvuser}@${hvip} 'yum -y -q remove cosmic-agent'
  # Remove running (System) VMs
  ${ssh_base} ${hvuser}@${hvip} 'vms=`virsh list --all --name`; for vm in `virsh list --all --name`; do virsh destroy ${vm}; done'
  ${ssh_base} ${hvuser}@${hvip} 'vms=`virsh list --all --name`; for vm in `virsh list --all --name`; do virsh undefine ${vm}; done'
  # Remove disk images from primary storage
  ${ssh_base} ${hvuser}@${hvip}  'rm -f `mount | grep primary | cut -d" " -f3`/*' >/dev/null
}
function usage {
  printf "\nUsage: %s: -m marvinCfg [ -s -v -t -T <mvn -T flag> ]\n\n" $(basename $0) >&2
  printf "\t-T:\tPass 'mvn -T ...' flags\n" >&2
  printf "\nFeature flags:\n" >&2
  printf "\t-I:\tRun integration tests\n" >&2
  printf "\t-D:\tEnable remote debugging on tomcat (port 8000)\n" >&2
  printf "\t-C:\tDon't use 'clean' target on maven build\n" >&2
  printf "\t-E:\tDon't use unit tests on maven build\n" >&2
  printf "\nSkip flags:\n" >&2
  printf "\t-s:\tSkip maven build and RPM packaging\n" >&2
  printf "\t-t:\tSkip maven build\n" >&2
  printf "\t-u:\tSkip RPM packaging\n" >&2
  printf "\t-v:\tSkip prepare infra (VM creation)\n" >&2
  printf "\t-w:\tSkip setup infra (DB creation, war deploy, agent-rpm installs)\n" >&2
  printf "\t-x:\tSkip deployDC\n" >&2
  printf "\nScenario\'s (will combine/override skip flags):\n" >&2
  printf "\t-a:\tMaven build and WAR (only) deploy\n" >&2
  printf "\t-b:\tRe-deploy DataCenter, including war and kvm agents, no re-build VMs, no re-build maven/rpm, (= -s -v)\n" >&2
  printf "\n" >&2
}
# Options
skip=0
skip_maven_build=0
skip_rpm_package=0
skip_prepare_infra=0
skip_setup_infra=0
skip_deploy_dc=0
run_tests=0
compile_threads=
scenario_build_deploy_new_war=0
scenario_redeploy_cosmic=0
disable_maven_clean=0
disable_maven_unit_tests=0
# Former options
enable_remote_debugging=1
while getopts 'abCEIm:T:stuvwx' OPTION
do
  case $OPTION in
  a)    scenario_build_deploy_new_war=1
        ;;
  b)    scenario_redeploy_cosmic=1
        ;;
  C)    disable_maven_clean=1
        ;;
  E)    disable_maven_unit_tests=1
        ;;
  m)    marvinCfg="$OPTARG"
        ;;
  s)    skip=1
        ;;
  t)    skip_maven_build=1
        ;;
  u)    skip_rpm_package=1
        ;;
  v)    skip_prepare_infra=1
        ;;
  w)    skip_setup_infra=1
        ;;
  x)    skip_deploy_dc=1
        ;;
  I)    run_tests=1
        ;;
  T)    compile_threads="-T $OPTARG"
        ;;
  esac
done

echo "Received arguments:"
echo "disable_maven_clean      (-C) = ${disable_maven_clean}"
echo "disable_maven_unit_tests (-E) = ${disable_maven_unit_tests}"
echo ""
echo "skip               (-s) = ${skip}"
echo "skip_maven_build   (-t) = ${skip_maven_build}"
echo "skip_rpm_package   (-u) = ${skip_rpm_package}"
echo "skip_prepare_infra (-v) = ${skip_prepare_infra}"
echo "skip_setup_infra   (-w) = ${skip_setup_infra}"
echo "skip_deploy_dc     (-x) = ${skip_deploy_dc}"
echo "run_tests          (-I) = ${run_tests}"
echo "marvinCfg          (-m) = ${marvinCfg}"
echo "compile_threads    (-T) = ${compile_threads}"
echo ""
echo "scenario_build_deploy_new_war (-a) = ${scenario_build_deploy_new_war}"
echo "scenario_redeploy_cosmic (-b)      = ${scenario_redeploy_cosmic}"
echo ""

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
if [ ${scenario_build_deploy_new_war} -eq 1 ]; then
  skip=0
  skip_maven_build=0
  skip_rpm_package=1
  skip_prepare_infra=1
  skip_setup_infra=1
  skip_deploy_dc=1
fi
if [ ${scenario_redeploy_cosmic} -eq 1 ]; then
  skip=1
  skip_maven_build=1
  skip_rpm_package=1
  skip_prepare_infra=1
  skip_setup_infra=0
  skip_deploy_dc=0
fi

# 00080 Parse marvin config
parse_marvin_config ${marvinCfg}
csip=$(getent hosts cs1 | awk '{ print $1 }')

# 000090 Set workspace
WORKSPACE=/data/git/${zone}
mkdir -p "${WORKSPACE}"
echo "Using workspace '${WORKSPACE}'."

COSMIC_BUILD_PATH=$WORKSPACE/cosmic
COSMIC_CORE_PATH=$COSMIC_BUILD_PATH/cosmic-core
PACKAGING_BUILD_PATH=$WORKSPACE/packaging
CI_SCRIPTS=/data/shared/ci


# 00060 We work from here
cd ${WORKSPACE}

# 00100 Checkout the code
cosmic_sources_retrieve ${WORKSPACE}

# 00110 Config nexus for maven
config_maven

# 00200 Build, unless told to skip
if [ ${skip} -eq 0 ] && [ ${skip_maven_build} -eq 0 ]; then
  # Compile Cosmic

  maven_build "$COSMIC_BUILD_PATH" "${compile_threads}" ${disable_maven_clean} ${disable_maven_unit_tests}

  if [ $? -ne 0 ]; then echo "Maven build failed!"; exit;  fi
else
  echo "Skipped maven build"
fi

# 00300 Package RPMs
if [ ${skip} -eq 0 ] && [ ${skip_rpm_package} -eq 0 ]; then
  if [[ "${hypervisor}" == "kvm" ]]; then

    rpm_package "${PACKAGING_BUILD_PATH}" "${COSMIC_BUILD_PATH}"

    if [ $? -ne 0 ]; then echo "RPM package failed!"; exit;  fi
    [ -h "${COSMIC_BUILD_PATH}/dist" ] || ln -s "${PACKAGING_BUILD_PATH}/dist" "${COSMIC_BUILD_PATH}/dist"
  else
    echo "No RPM packages needed for ${hypervisor}"
  fi
else
  echo "Skipped RPM packaging"
fi
# 00400 Prepare Infra, create VMs
if [ ${skip_prepare_infra} -eq 0 ]; then

  # JENKINS: prepareInfraForIntegrationTests: not implemented: shell('rm -rf ./*')
  "${CI_SCRIPTS}/ci-prepare-infra.sh" -m "${marvinCfg}"

else
  echo "Skipped prepare infra"
fi

if [ ${enable_remote_debugging} -eq 1 ]; then
  enable_remote_debug_kvm ${hvip1} ${hvuser1} ${hvpass1}
  enable_remote_debug_kvm ${hvip2} ${hvuser2} ${hvpass2}
fi

# 00500 Setup Infra
if [ ${skip_setup_infra} -eq 0 ]; then
  cd "${COSMIC_BUILD_PATH}"
  rm -rf "$secondarystorage/*"
  # Cleanup CS in case of re-deploy
  cleanup_cs ${csip} "root" "password"

  # Clean KVMs in case of re-deploy
  cleanup_kvm ${hvip1} ${hvuser1} ${hvpass1}
  cleanup_kvm ${hvip2} ${hvuser2} ${hvpass2}

  # JENKINS: setupInfraForIntegrationTests: no change
  "${CI_SCRIPTS}/ci-setup-infra.sh" -m "${marvinCfg}"

else
  echo "Skipped setup infra"
fi

# 00510 Setup only war deploy
# Jenkins: war deploy is part of setupInfraForIntegrationTests
if [ ${scenario_build_deploy_new_war} -eq 1 ]; then
  cd "${COSMIC_BUILD_PATH}"
  undeploy_cloudstack_war ${csip} "root" "password"
  deploy_cloudstack_war ${csip} "root" "password" 'cosmic-client/target/setup/db/db/*' 'cosmic-client/target/cloud-client-ui-*.war'
fi

if [ ${enable_remote_debugging} -eq 1 ]; then
  enable_remote_debug_war ${csip} "root" "password"
fi


# 00600 Deploy DC
if [ ${skip_deploy_dc} -eq 0 ]; then
  cd ${WORKSPACE}
  rm -rf "$primarystorage/*"

  # JENKINS: deployDatacenterForIntegrationTests: no change other then moving log files around for archiveArtifacts
  "${CI_SCRIPTS}/ci-deploy-data-center.sh" -m "${marvinCfg}"

else
  echo "Skipped deployDC"
fi

# 00700 Run tests
if [ ${run_tests} -eq 1 ]; then
  cd "${COSMIC_BUILD_PATH}"

  # JENKINS: runIntegrationTests: no change, tests inserted from injectJobVariable(flattenLines(TESTS_PARAM))
  "${CI_SCRIPTS}/ci-run-marvin-tests.sh" -m "${marvinCfg}" -h true smoke/test_network.py smoke/test_routers_iptables_default_policy.py smoke/test_password_server.py smoke/test_vpc_redundant.py smoke/test_routers_network_ops.py smoke/test_vpc_router_nics.py smoke/test_router_dhcphosts.py smoke/test_loadbalance.py smoke/test_privategw_acl.py smoke/test_ssvm.py smoke/test_vpc_vpn.py
else
  echo "Skipped tests"
fi

echo "Finished"
date

