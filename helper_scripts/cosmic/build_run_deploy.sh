#!/bin/bash
set -e

# This script builds and runs Cosmic and deploys a data center using the supplied Marvin config.
# When KVM is used Cosmic Agent is installed on the hypervisor.

# Source the helper functions
. `dirname $0`/helperlib.sh

# Reference to ci scripts
scripts_dir="$(dirname $0)/../../ci"

function usage {
  printf "\nUsage: %s: -m marvinCfg [ -s -v -t -T <mvn -T flag> ]\n\n" $(basename $0) >&2
  printf "\t-m:\tMarvin config\n" >&2
  printf "\t-T:\tPass 'mvn -T ...' flags\n" >&2
  printf "\t-W:\tOverride workspace folder\n" >&2
  printf "\t-V:\tVerbose logging\n" >&2
  printf "\t-D:\tShell debugging\n" >&2
  printf "\t-o:\tSuspend management server on startup (DEBUG)\n" >&2
  printf "\t-p:\tSuspend kvm hypervisor on startup (DEBUG)" >&2
  printf "\nFeature flags:\n" >&2
  printf "\t-I:\tRun integration tests\n" >&2
  printf "\t-C:\tDon't use 'clean' target on maven build\n" >&2
  printf "\t-E:\tDon't use unit tests on maven build\n" >&2
  printf "\t-H:\tGit use HTTPS instead of SSH\n" >&2
  printf "\t-S:\t(Experimental) make use of cosmic-microservices"
  printf "\nSkip flags Cosmic:\n" >&2
  printf "\t-s:\tSkip Cosmic build and deploy entirely\n" >&2
  printf "\t-t:\tSkip maven build\n" >&2
  printf "\t-v:\tSkip prepare infra (VM creation)\n" >&2
  printf "\t-w:\tSkip setup infra (DB creation, war deploy, agent-rpm installs)\n" >&2
  printf "\t-x:\tSkip deploy DC\n" >&2
  printf "\nSkip flags Cosmic Microservices:\n" >&2
  printf "\t-k:\tSkip deploy minikube\n" >&2
  printf "\t-K:\tKeep previous minikube infra\n" >&2
  printf "\nScenario\'s (will combine/override skip flags):\n" >&2
  printf "\t-a:\tMaven build and WAR (only) deploy\n" >&2
  printf "\t-b:\tRe-deploy DataCenter, including war and kvm agents, no re-build VMs, no re-build maven, (= -t -v)\n" >&2
  printf "\n" >&2
}
# Options
scenario_build_deploy_new_war="false"
scenario_redeploy_cosmic=0
disable_maven_clean=0
maven_clean="clean"
shell_debugging="false"
shell_debugging_flag=""
disable_maven_unit_tests=0
maven_unit_tests=""
gitssh=1
run_tests=0
skip_deploy_minikube=0
remove_minikube_infra="true"
debug_war_startup=0
debug_kvm_startup=0
enable_cosmic_microservices=0
skip_cosmic_entirely="false"
skip_maven_build=0
compile_threads=
skip_prepare_infra=0
verbose=0
skip_setup_infra=0
WORKSPACE_OVERRIDE=
skip_deploy_dc=0

while getopts 'abCDEHIkKm:opsStT:vVwW:x' OPTION
do
  case $OPTION in
  a)    scenario_build_deploy_new_war="true"
        ;;
  b)    scenario_redeploy_cosmic=1
        ;;
  C)    disable_maven_clean=1
        maven_clean=""
        ;;
  D)    shell_debugging="true"
        set -x
        shell_debugging_flag="-x"
        ;;
  E)    disable_maven_unit_tests=1
        maven_unit_tests=" -DskipTests "
        ;;
  H)    gitssh=0
        ;;
  I)    run_tests=1
        ;;
  k)    skip_deploy_minikube=1
        ;;
  K)    remove_minikube_infra="false"
        ;;
  m)    marvinCfg="$OPTARG"
        ;;
  o)    debug_war_startup=1
        ;;
  p)    debug_kvm_startup=1
        ;;
  s)    skip_cosmic_entirely="true"
        ;;
  S)    enable_cosmic_microservices=1
        ;;
  t)    skip_maven_build=1
        ;;
  T)    compile_threads="-T $OPTARG"
        ;;
  v)    skip_prepare_infra=1
        ;;
  V)    verbose=1
        ;;
  w)    skip_setup_infra=1
        ;;
  W)    WORKSPACE_OVERRIDE="$OPTARG"
        ;;
  x)    skip_deploy_dc=1
        ;;
  esac
done

if [ ${verbose} -eq 1 ]; then
  echo "Received arguments:"
  echo "disable_maven_clean           (-C) = ${disable_maven_clean}"
  echo "disable_maven_unit_tests      (-E) = ${disable_maven_unit_tests}"
  echo "WORKSPACE_OVERRIDE            (-W) = ${WORKSPACE_OVERRIDE}"
  echo "shell_debugging               (-D) = ${shell_debugging}"
  echo "gitssh                        (-H) = ${gitssh}"
  echo ""
  echo "skip_cosmic_entirely          (-s) = ${skip_cosmic_entirely}"
  echo "skip_maven_build              (-t) = ${skip_maven_build}"
  echo "skip_prepare_infra            (-v) = ${skip_prepare_infra}"
  echo "skip_setup_infra              (-w) = ${skip_setup_infra}"
  echo "skip_deploy_dc                (-x) = ${skip_deploy_dc}"
  echo "skip_deploy_minikube          (-k) = ${skip_deploy_minikube}"
  echo "remove_minikube_infra         (-K) = ${remove_minikube_infra}"
  echo "run_tests                     (-I) = ${run_tests}"
  echo "marvinCfg                     (-m) = ${marvinCfg}"
  echo "compile_threads               (-T) = ${compile_threads}"
  echo "debug_war_startup             (-o) = ${debug_war_startup}"
  echo "debug_kvm_startup             (-p) = ${debug_kvm_startup}"
  echo ""
  echo "scenario_build_deploy_new_war (-a) = ${scenario_build_deploy_new_war}"
  echo "scenario_redeploy_cosmic      (-b) = ${scenario_redeploy_cosmic}"
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
if [ ${scenario_build_deploy_new_war} == "true" ]; then
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
if [ ${skip_cosmic_entirely} == "true" ]; then
  skip_maven_build=1
  skip_prepare_infra=1
  skip_prepare_infra=1
  skip_setup_infra=1
  skip_deploy_dc=1
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

# Cosmic Microservices Build Path
COSMIC_MS_BUILD_PATH=${WORKSPACE}/cosmic-microservices

# Cosmic Microservices Charts Path
COSMIC_MS_CHART_PATH=${WORKSPACE}/cosmic-microservices-chart

# 00060 We (not Jenkins) work from here
cd ${WORKSPACE}

# 00100 Checkout the code
if [ ${skip_cosmic_entirely} == "false" ]; then
  cosmic_sources_retrieve ${WORKSPACE} ${gitssh}
fi
if [ ${enable_cosmic_microservices} -eq 1 ]; then
  cosmic_microservices_sources_retrieve ${WORKSPACE} ${gitssh}
  cosmic_microservices_charts_retrieve ${WORKSPACE} ${gitssh}
fi

# 00110 Config nexus for maven
config_maven

# 00400 Prepare Infra, create VMs
if [ ${skip_prepare_infra} -eq 0 ]; then
  PREP_INFRA_LOG=/tmp/prep_infra_${$}.log
  echo "Executing prepare-infra in background, logging: ${PREP_INFRA_LOG}"
  # JENKINS: prepareInfraForIntegrationTests: not implemented: shell('rm -rf ./*')
  sh ${shell_debugging_flag} "${CI_SCRIPTS}/ci-prepare-infra.sh" -m "${marvinCfg}"  2>&1 > ${PREP_INFRA_LOG}    &
  PREP_INFRA_PID=$!
else
  echo "Skipped prepare infra"
fi

# 00450 Prepare minikube
if [ ${enable_cosmic_microservices} -eq 1 ]; then
  if [ ${skip_deploy_minikube} -eq 0 ]; then
    PREP_MINIKUBE_LOG=/tmp/prep_minikube_${$}.log
    echo "Executing prepare-minikube in background, logging: ${PREP_MINIKUBE_LOG}"
    sh ${shell_debugging_flag} "${CI_SCRIPTS}/ci-prepare-minikube.sh" ${remove_minikube_infra} 2>&1 > ${PREP_MINIKUBE_LOG}    &
    PREP_MINIKUBE_PID=$!
  else
    echo "Skipped prepare minikube."
  fi

  if [ "${remove_minikube_infra}" == "false" ]; then
    echo "Minikube infra retained, cleanup..."
    if [[ $(kubectl get secret --all-namespaces | egrep logstash-files) = *logstash-files* ]]; then
      kubectl delete secret --namespace=cosmic logstash-files
    fi
  fi
fi

# 00200 Build, unless told to skip
if [ ${skip_maven_build} -eq 0 ]; then
  # Compile Cosmic

  maven_build "$COSMIC_BUILD_PATH" "${compile_threads}" ${disable_maven_clean} ${disable_maven_unit_tests}

  if [ $? -ne 0 ]; then echo "Maven build failed!"; exit;  fi
else
  echo "Skipped Cosmic maven build"
fi

# ----- Wait for minikube
if [ ${enable_cosmic_microservices} -eq 1 ]; then
  if [ ${skip_deploy_minikube} -eq 0 ]; then
    echo "Waiting for prepare-minikube to be ready."
    wait ${PREP_MINIKUBE_PID}
    echo "Prepare-minikube console output:"
    cat  ${PREP_MINIKUBE_LOG}
  fi
fi

# Build cosmic-microservices
if [ ${enable_cosmic_microservices} -eq 1 ]; then
  minikube_get_ip &> /dev/null
  cd "${COSMIC_MS_BUILD_PATH}"
  mvn ${maven_clean} install -P development ${maven_unit_tests}\
      -Ddocker.host=unix:/var/run/docker.sock
  mvn docker:push -P development \
      -Ddocker.host=unix:/var/run/docker.sock \
      -Ddocker.push.registry=${MINIKUBE_HOST}:30081 \
      -Ddocker.filter=cosmic-config-server,cosmic-metrics-collector,cosmic-usage-api
  cd "${COSMIC_MS_BUILD_PATH}/cosmic-usage-ui"
  docker build -t ${MINIKUBE_HOST}:30081/missioncriticalcloud/cosmic-usage-ui .
  docker push ${MINIKUBE_HOST}:30081/missioncriticalcloud/cosmic-usage-ui
  cd "${COSMIC_MS_BUILD_PATH}"
fi

# 00550 Setup minikube
if [ ${enable_cosmic_microservices} -eq 1 ]; then
  if [ ${skip_deploy_minikube} -eq 0 ]; then
    say "Setting up minikube."
    cd "${COSMIC_MS_CHART_PATH}"
    sh ${shell_debugging_flag}  "${CI_SCRIPTS}/ci-setup-minikube.sh"
  else
    echo "Skipped setup minikube"
  fi
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

if [[ "${hypervisor}" == "kvm" ]]; then
  for i in 1 2 3 4 5 6 7 8 9; do
    if  [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
      hvuser=
      hvip=
      hvpass=
      eval hvuser="\${hvuser${i}}"
      eval hvip="\${hvip${i}}"
      eval hvpass="\${hvpass${i}}"
      enable_remote_debug_kvm ${hvip} ${hvuser} ${hvpass} ${debug_kvm_startup}
    fi
  done
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
      eval cspass="\${cs${i}pass}"
      # Cleanup CS in case of re-deploy
      say "Cleanup ${csip}"
      cleanup_cs ${csip} ${csuser} ${cspass}
      enable_remote_debug_war ${csip} ${csuser} ${cspass} ${debug_war_startup}
    fi

    if [[ "${hypervisor}" == "kvm" ]]; then
      # Clean KVMs in case of re-deploy
      if [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
        hvuser=
        hvip=
        hvpass=
        eval hvuser="\${hvuser${i}}"
        eval hvip="\${hvip${i}}"
        eval hvpass="\${hvpass${i}}"
        say "Cleanup ${hvip}"
        cleanup_kvm ${hvip} ${hvuser} ${hvpass}
      fi
    fi
  done

  # Remove images from primary storage
  [[ ${primarystorage} == '/data/storage/primary/'* ]] && [ -d ${primarystorage} ] && sudo rm -rf ${primarystorage}/*

  # JENKINS: setupInfraForIntegrationTests: no change
  sh ${shell_debugging_flag} "${CI_SCRIPTS}/ci-setup-infra.sh" -m "${marvinCfg}"
else
  echo "Skipped setup infra"
fi

cd "${COSMIC_BUILD_PATH}"
if [ ${scenario_build_deploy_new_war} == "true" ]; then

  for i in 1 2 3 4 5 6 7 8 9; do
    if [ ! -v $( eval "echo \${cs${i}ip}" ) ]; then
      csuser=
      csip=
      cspass=
      eval csuser="\${cs${i}user}"
      eval csip="\${cs${i}ip}"
      eval cspass="\${cs${i}pass}"

      # 00510 Setup only war deploy
      # Jenkins: war deploy is part of setupInfraForIntegrationTests
      say "Deploy new war to ${csip}"

      # Cleanup CS in case of re-deploy
      undeploy_cosmic_war ${csip} ${csuser} ${cspass}
      enable_remote_debug_war ${csip} ${csuser} ${cspass} ${debug_war_startup}
      deploy_cosmic_war ${csip} ${csuser} ${cspass} 'cosmic-client/target/cloud-client-ui-*.war'
    fi

    if [[ "${hypervisor}" == "kvm" ]]; then
      if  [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
        hvuser=
        hvip=
        hvpass=
        eval hvuser="\${hvuser${i}}"
        eval hvip="\${hvip${i}}"
        eval hvpass="\${hvpass${i}}"
        say "Installing Cosmic KVM Agent on host ${hvip}"
        install_kvm_packages ${hvip} ${hvuser} ${hvpass} ${scenario_build_deploy_new_war}
      fi
    fi
  done
fi

# 00600 Deploy DC
if [ ${skip_deploy_dc} -eq 0 ]; then
  cd ${WORKSPACE}
  rm -rf "$primarystorage/*"

  # JENKINS: deployDatacenterForIntegrationTests: no change other then moving log files around for archiveArtifacts
  sh ${shell_debugging_flag} "${CI_SCRIPTS}/ci-deploy-data-center.sh" -m "${marvinCfg}"

else
  echo "Skipped deployDC"
fi

# 00700 Run tests
if [ ${run_tests} -eq 1 ]; then
  cd "${COSMIC_BUILD_PATH}"

  # JENKINS: runIntegrationTests: no change, tests inserted from injectJobVariable(flattenLines(TESTS_PARAM))
  sh ${shell_debugging_flag} "${CI_SCRIPTS}/ci-run-marvin-tests.sh" -m "${marvinCfg}" -h true smoke/test_network.py smoke/test_routers_iptables_default_policy.py smoke/test_password_server.py smoke/test_vpc_redundant.py smoke/test_routers_network_ops.py smoke/test_vpc_router_nics.py smoke/test_router_dhcphosts.py smoke/test_loadbalance.py smoke/test_privategw_acl.py smoke/test_ssvm.py smoke/test_vpc_vpn.py
else
  echo "Skipped tests"
fi

echo "Finished"
date
