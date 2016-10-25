#!/bin/bash

# This script builds and runs Cosmic and deploys a data center using the supplied Marvin config.
# When KVM is used Cosmic Agent is installed on the hypervisor.

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

# Reference to ci scripts
scripts_dir="$(dirname $0)/../../ci"


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

  management_server_log_file="/var/log/cosmic/management/management.log"
  management_server_log_rotation="/var/log/cosmic/management/management-%d{yyyy-MM-dd}.log.gz"
  mvn_cmd="mvn ${maven_clean} install -P systemvm,sonar-ci-cosmic ${compile_threads} "
  mvn_cmd="${mvn_cmd} -Dcosmic.dir=${build_dir} -Dlog.file.management.server=${management_server_log_file} -Dlog.rotation.management.server=${management_server_log_rotation} "
  mvn_cmd="${mvn_cmd} ${maven_unit_tests}"

  echo ${mvn_cmd}
  # JENKINS: mavenBuild: maven job with goals: clean install deploy -U -Psystemvm -Psonar-ci-cosmic -Dcosmic.dir=\"${injectJobVariable(CUSTOM_WORKSPACE_PARAM)}\"
  # Leaving out deploy and -U (Forces a check for updated releases and snapshots on remote repositories)
  eval "${mvn_cmd}"
  if [ $? -ne 0 ]; then
    date
    echo "Build failed, please investigate!"
    exit 1
  fi
  cd "${pwd}"
  date
}

# deploy_cloudstack_war should be sourced from ci-deploy-infra.sh, but contains executing code
# so should be moved to a "library" sh script which can be sourced
function deploy_cloudstack_war {
  local csip=$1
  local csuser=$2
  local cspass=$3
  local war_file="$4"

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "
  # Extra configuration for Tomcat's webapp (namely adding /etc/cosmic/management to its classpath)
  ${scp_base} ${CI_SCRIPTS}/setup_files/client.xml ${csuser}@${csip}:~tomcat/conf/Catalina/localhost/

  # Extra configuration for Cosmic application
  ${ssh_base} ${csuser}@${csip} mkdir -p /etc/cosmic/management
  ${scp_base} ${scripts_dir}/setup_files/db.properties ${csuser}@${csip}:/etc/cosmic/management
  ${ssh_base} ${csuser}@${csip} "sed -i \"s/cluster.node.IP=.*\$/cluster.node.IP=${csip}/\" /etc/cosmic/management/db.properties"

  ${ssh_base} ${csuser}@${csip} mkdir -p /var/log/cosmic/management
  ${ssh_base} ${csuser}@${csip} chown -R tomcat /var/log/cosmic
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
  ${ssh_base} ${csuser}@${csip} rm -rf /var/log/cosmic/
  ${ssh_base} ${csuser}@${csip} rm -rf /etc/cosmic/management
}

function enable_remote_debug_war {
  local csip=$1
  local csuser=$2
  local cspass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  ${ssh_base} ${csuser}@${csip}  'if ! grep -q CATALINA_OPTS /etc/tomcat/tomcat.conf; then echo '\''CATALINA_OPTS="-agentlib:jdwp=transport=dt_socket,address=8000,server=y,suspend=n"'\'' >> /etc/tomcat/tomcat.conf; echo Configuring DEBUG access for management server; fi'
}
function enable_remote_debug_kvm {
  local hvip=$1
  local hvuser=$2
  local hvpass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  ${ssh_base} ${hvuser}@${hvip}  'if [ ! -f /etc/systemd/system/cosmic-agent.service.d/debug.conf ]; then echo Configuring DEBUG access for KVM server; mkdir -p /etc/systemd/system/cosmic-agent.service.d/; printf "[Service]\nEnvironment=JAVA_REMOTE_DEBUG=-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000" > /etc/systemd/system/cosmic-agent.service.d/debug.conf; systemctl daemon-reload; fi'
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

  # Remove running (System) VMs
  ${ssh_base} ${hvuser}@${hvip} 'vms=`virsh list --all --name`; for vm in `virsh list --all --name`; do virsh destroy ${vm}; done'
  ${ssh_base} ${hvuser}@${hvip} 'vms=`virsh list --all --name`; for vm in `virsh list --all --name`; do virsh undefine ${vm}; done'
}
function usage {
  printf "\nUsage: %s: -m marvinCfg [ -s -v -t -T <mvn -T flag> ]\n\n" $(basename $0) >&2
  printf "\t-m:\tMarvin config\n" >&2
  printf "\t-T:\tPass 'mvn -T ...' flags\n" >&2
  printf "\t-W:\tOverride workspace folder\n" >&2
  printf "\t-V:\tVerbose logging" >&2
  printf "\nFeature flags:\n" >&2
  printf "\t-I:\tRun integration tests\n" >&2
  printf "\t-D:\tEnable remote debugging on tomcat (port 8000)\n" >&2
  printf "\t-C:\tDon't use 'clean' target on maven build\n" >&2
  printf "\t-E:\tDon't use unit tests on maven build\n" >&2
  printf "\t-H:\tGit use HTTPS instead of SSH\n" >&2
  printf "\nSkip flags:\n" >&2
  printf "\t-t:\tSkip maven build\n" >&2
  printf "\t-v:\tSkip prepare infra (VM creation)\n" >&2
  printf "\t-w:\tSkip setup infra (DB creation, war deploy, agent-rpm installs)\n" >&2
  printf "\t-x:\tSkip deploy DC\n" >&2
  printf "\t-k:\tSkip deploy minikube\n" >&2
  printf "\nScenario\'s (will combine/override skip flags):\n" >&2
  printf "\t-a:\tMaven build and WAR (only) deploy\n" >&2
  printf "\t-b:\tRe-deploy DataCenter, including war and kvm agents, no re-build VMs, no re-build maven, (= -t -v)\n" >&2
  printf "\n" >&2
}
# Options
skip_maven_build=0
skip_prepare_infra=0
skip_setup_infra=0
skip_deploy_dc=0
skip_deploy_minikube=0
run_tests=0
compile_threads=
scenario_build_deploy_new_war=0
scenario_redeploy_cosmic=0
disable_maven_clean=0
disable_maven_unit_tests=0
enable_remote_debugging=1
gitssh=1
verbose=0
WORKSPACE_OVERRIDE=

while getopts 'abCEHIm:T:tvVwW:x' OPTION
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
  H)    gitssh=0
        ;;
  V)    verbose=1
        ;;
  W)    WORKSPACE_OVERRIDE="$OPTARG"
        ;;
  m)    marvinCfg="$OPTARG"
        ;;
  t)    skip_maven_build=1
        ;;
  v)    skip_prepare_infra=1
        ;;
  w)    skip_setup_infra=1
        ;;
  x)    skip_deploy_dc=1
        ;;
  k)    skip_deploy_minikube=1
        ;;
  I)    run_tests=1
        ;;
  T)    compile_threads="-T $OPTARG"
        ;;
  esac
done

if [ ${verbose} -eq 1 ]; then
  echo "Received arguments:"
  echo "disable_maven_clean      (-C) = ${disable_maven_clean}"
  echo "disable_maven_unit_tests (-E) = ${disable_maven_unit_tests}"
  echo "WORKSPACE_OVERRIDE       (-W) = ${WORKSPACE_OVERRIDE}"
  echo "gitssh                   (-H) = ${gitssh}"
  echo ""
  echo "skip_maven_build     (-t) = ${skip_maven_build}"
  echo "skip_prepare_infra   (-v) = ${skip_prepare_infra}"
  echo "skip_setup_infra     (-w) = ${skip_setup_infra}"
  echo "skip_deploy_dc       (-x) = ${skip_deploy_dc}"
  echo "skip_deploy_minikube (-k) = ${skip_deploy_minikube}"
  echo "run_tests            (-I) = ${run_tests}"
  echo "marvinCfg            (-m) = ${marvinCfg}"
  echo "compile_threads      (-T) = ${compile_threads}"
  echo ""
  echo "scenario_build_deploy_new_war (-a) = ${scenario_build_deploy_new_war}"
  echo "scenario_redeploy_cosmic (-b)      = ${scenario_redeploy_cosmic}"
  echo ""
fi
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
  skip_maven_build=0
  skip_prepare_infra=1
  skip_setup_infra=1
  skip_deploy_dc=1
fi
if [ ${scenario_redeploy_cosmic} -eq 1 ]; then
  skip_maven_build=1
  skip_prepare_infra=1
  skip_setup_infra=0
  skip_deploy_dc=0
fi

# 00080 Parse marvin config
parse_marvin_config ${marvinCfg}

# 000090 Set workspace
if [ -n "${WORKSPACE_OVERRIDE}" ]; then
  WORKSPACE=${WORKSPACE_OVERRIDE}
else
  WORKSPACE=/data/git/${zone}
fi
mkdir -p "${WORKSPACE}"
echo "Using workspace '${WORKSPACE}'."

COSMIC_BUILD_PATH=$WORKSPACE/cosmic
COSMIC_CORE_PATH=$COSMIC_BUILD_PATH/cosmic-core
PACKAGING_BUILD_PATH=$WORKSPACE/packaging
CI_SCRIPTS=/data/shared/ci


# 00060 We work from here
cd ${WORKSPACE}

# 00100 Checkout the code
cosmic_sources_retrieve ${WORKSPACE} ${gitssh}

# 00110 Config nexus for maven
config_maven

# 00400 Prepare Infra, create VMs
if [ ${skip_prepare_infra} -eq 0 ]; then
  PREP_INFRA_LOG=/tmp/prep_infra_${$}.log
  echo "Executing prepare-infra in background, logging: ${PREP_INFRA_LOG}"
  # JENKINS: prepareInfraForIntegrationTests: not implemented: shell('rm -rf ./*')
  "${CI_SCRIPTS}/ci-prepare-infra.sh" -m "${marvinCfg}"  2>&1 > ${PREP_INFRA_LOG}    &
  PREP_INFRA_PID=$!
else
  echo "Skipped prepare infra"
fi

# 00450 Prepare minikube
if [ ${skip_deploy_minikube} -eq 0 ]; then
  "${CI_SCRIPTS}/ci-prepare-minikube.sh"
else
  echo "Skipped prepare minikube"
fi

# 00200 Build, unless told to skip
if [ ${skip_maven_build} -eq 0 ]; then
  # Compile Cosmic

  maven_build "$COSMIC_BUILD_PATH" "${compile_threads}" ${disable_maven_clean} ${disable_maven_unit_tests}

  if [ $? -ne 0 ]; then echo "Maven build failed!"; exit;  fi
else
  echo "Skipped maven build"
fi

# 00400 Prepare Infra, create VMs
if [ ${skip_prepare_infra} -eq 0 ]; then
  echo "Waiting for prepare-infra to be ready, logging: ${PREP_INFRA_LOG}"
  wait ${PREP_INFRA_PID}
  PREP_INFRA_RETURN=$?
  echo "Prepare-infra returned ${PREP_INFRA_RETURN}"
  echo "Prepare-infra console output:"
  cat  ${PREP_INFRA_LOG}
  rm ${PREP_INFRA_LOG}
  if [ "${PREP_INFRA_RETURN}" -ne 0 ]; then echo "Prepare-infra failed!"; exit;  fi
fi

if [ ${enable_remote_debugging} -eq 1 ]; then
  for i in 1 2 3 4 5 6 7 8 9; do
    if  [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
      hvuser=
      hvip=
      hvpass=
      eval hvuser="\${hvuser${i}}"
      eval hvip="\${hvip${i}}"
      eval hvpass="\${hvpass${i}}"
      enable_remote_debug_kvm ${hvip} ${hvuser} ${hvpass}
    fi
  done
fi

# 00550 Setup minikube
if [ ${skip_deploy_minikube} -eq 0 ]; then
  "${CI_SCRIPTS}/ci-setup-minikube.sh"
else
  echo "Skipped setup minikube"
fi

# 00500 Setup Infra
if [ ${skip_setup_infra} -eq 0 ]; then
  cd "${COSMIC_BUILD_PATH}"
  rm -rf "$secondarystorage/*"

  for i in 1 2 3 4 5 6 7 8 9; do
    # Cleanup CS in case of re-deploy
    if [ ! -v $( eval "echo \${cs${i}ip}" ) ]; then
      csuser=
      csip=
      cspass=
      eval csuser="\${cs${i}user}"
      eval csip="\${cs${i}ip}"
      eval cspass="\${cs${i}ip}"
      # Cleanup CS in case of re-deploy
      cleanup_cs ${csip} ${csuser} ${cspass}
    fi

    # Clean KVMs in case of re-deploy
    if [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
      hvuser=
      hvip=
      hvpass=
      eval hvuser="\${hvuser${i}}"
      eval hvip="\${hvip${i}}"
      eval hvpass="\${hvpass${i}}"
      cleanup_kvm ${hvip} ${hvuser} ${hvpass}
    fi
  done

  # Remove images from primary storage
  [[ ${primarystorage} == '/data/storage/primary/'* ]] && [ -d ${primarystorage} ] && sudo rm -rf ${primarystorage}/*

  # JENKINS: setupInfraForIntegrationTests: no change
  "${CI_SCRIPTS}/ci-setup-infra.sh" -m "${marvinCfg}"

else
  echo "Skipped setup infra"
fi

cd "${COSMIC_BUILD_PATH}"
for i in 1 2 3 4 5 6 7 8 9; do
  if [ ! -v $( eval "echo \${cs${i}ip}" ) ]; then
    csuser=
    csip=
    cspass=
    eval csuser="\${cs${i}user}"
    eval csip="\${cs${i}ip}"
    eval cspass="\${cs${i}ip}"

    if [ ${enable_remote_debugging} -eq 1 ]; then
      enable_remote_debug_war ${csip} ${csuser} ${cspass}
    fi

    if [ ${scenario_build_deploy_new_war} -eq 1 ]; then
      # 00510 Setup only war deploy
      # Jenkins: war deploy is part of setupInfraForIntegrationTests

      # Cleanup CS in case of re-deploy
      undeploy_cloudstack_war ${csip} ${csuser} ${cspass}
      deploy_cloudstack_war ${csip} ${csuser} ${cspass} 'cosmic-client/target/cloud-client-ui-*.war'
    fi
  fi
done


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
