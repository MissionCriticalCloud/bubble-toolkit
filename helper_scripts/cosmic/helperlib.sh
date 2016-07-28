#!/bin/sh
HELPERLIB_SH_SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

host_ip=`ip addr | grep 'inet 192' | cut -d: -f2 | awk '{ print $2 }' | awk -F\/24 '{ print $1 }'`

function cosmic_sources_retrieve {
  BASEDIR=$1
  GITSSH=$2
  gitclone_recursive 'git@github.com:MissionCriticalCloud/cosmic.git' "${BASEDIR}/cosmic"  ${GITSSH}
}

function gitclone_recursive {
  REPO_URL=$1
  CHECKOUT_PATH=$2
  GIT_SSH=$3

  mkdir -p "${CHECKOUT_PATH}"
  if [ ! -d "${CHECKOUT_PATH}/.git" ]; then
    echo "No git repo found at ${CHECKOUT_PATH}, cloning ${REPO_URL}"
  if [ -z ${GIT_SSH} ] || [ "${GIT_SSH}" -eq "1" ]; then
    git clone --recursive "${REPO_URL}" "${CHECKOUT_PATH}"
    else
      git clone `echo ${REPO_URL} | sed 's@git\@github.com:@https://github.com/@'` "${CHECKOUT_PATH}"
      cwd=$(pwd)
      cd "${CHECKOUT_PATH}"
      git submodule init
      sed -i 's@git\@github.com:@https://github.com/@' .git/config
      git submodule update
      cd "${cwd}"
    fi
    echo "Please use 'git checkout' to checkout the branch you need."
  else
    echo "Git repo already found at ${CHECKOUT_PATH}"
  fi
}

function gitclone {
  REPO_URL=$1
  CHECKOUT_PATH=$2
  GIT_SSH=$3
  mkdir -p "${CHECKOUT_PATH}"
  if [ ! -d "${CHECKOUT_PATH}/.git" ]; then
    echo "No git repo found at ${CHECKOUT_PATH}, cloning ${REPO_URL}"
    if [ -z ${GIT_SSH} ] || [ "${GIT_SSH}" -eq "1" ]; then
      git clone "${REPO_URL}" "${CHECKOUT_PATH}"
    else
      git clone `echo ${REPO_URL} | sed 's@git\@github.com:@https://github.com/@'` "${CHECKOUT_PATH}"
    fi
    echo "Please use 'git checkout' to checkout the branch you need."
  else
    echo "Git repo already found at ${CHECKOUT_PATH}"
  fi
}

function wget_fetch {
  if [ ! -f "$2" ]; then
    echo "Fetching $1"
    wget "$1" -O "$2"
  fi
}

function config_maven {
  if [ ! -f ~/.m2/settings.xml ]; then
    if [ ! -d ~/.m2 ]; then
      mkdir ~/.m2
    fi
    cp "${HELPERLIB_SH_SOURCE_DIR}/config/maven_settings.xml" ~/.m2/settings.xml
  fi
}

function install_kvm_packages {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  if [  -d /data/git/$HOSTNAME/packaging/dist/rpmbuild/RPMS/x86_64 ]; then
    distdir=/data/git/$HOSTNAME/packaging/dist/rpmbuild/RPMS/x86_64
  else
    if [  -d ../dist/rpmbuild/RPMS/x86_64 ]; then
      distdir=../dist/rpmbuild/RPMS/x86_64
    fi
  fi

  echo "Dist dir is ${distdir}"

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # scp packages to hypervisor, remove existing, then install new ones
  ${ssh_base} ${hvuser}@${hvip} rm cosmic-*
  ${scp_base} ${distdir}/* ${hvuser}@${hvip}:
  ${ssh_base} ${hvuser}@${hvip} yum -y remove cosmic-common
  ${ssh_base} ${hvuser}@${hvip} rm -f /etc/cosmic/agent/agent.properties
  ${ssh_base} ${hvuser}@${hvip} yum -y localinstall cosmic-agent* cosmic-common*
  # Use OVS networking
  ${ssh_base} ${hvuser}@${hvip} 'echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "network.bridge.type=openvswitch" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.cpu.mode=host-model" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "public.network.device=pub0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "private.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'
  # Enable debug logging
  ${ssh_base} ${hvuser}@${hvip} sed -i 's/INFO/DEBUG/g' /etc/cosmic/agent/log4j-cloud.xml
  # Enable remote debugging
  ${ssh_base} ${hvuser}@${hvip} mkdir -p /etc/systemd/system/cosmic-agent.service.d/
  ${ssh_base} ${hvuser}@${hvip} 'printf "[Service]\nEnvironment=JAVA_REMOTE_DEBUG=-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000" > /etc/systemd/system/cosmic-agent.service.d/debug.conf'
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload
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
  ${ssh_base} ${hvuser}@${hvip} systemctl stop cosmic-agent
  ${ssh_base} ${hvuser}@${hvip} systemctl disable cosmic-agent
  ${ssh_base} ${hvuser}@${hvip} systemctl restart libvirtd
  ${ssh_base} ${hvuser}@${hvip} sed -i 's/INFO/DEBUG/g' /etc/cosmic/agent/log4j-cloud.xml
  ${ssh_base} ${hvuser}@${hvip} "for host in \$(virsh list | awk '{print \$2;}' | grep -v Name |egrep -v '^\$'); do virsh destroy \$host; done"
}

function clean_xenserver {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  /data/shared/helper_scripts/cleaning/xapi_cleanup_xenservers.py http://${hvip} ${hvuser} ${hvpass}

}

function parse_marvin_config {
  #Parameters
  marvinCfg=$1

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

  secondarystorage=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['secondaryStorages'][0]['url']" | cut -d: -f3
  )

  for i in 1 2 3 4 5 6 7 8 9
  do
  # username hypervisor 1
  export hvuser${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][${i}-1]['username']
except:
  print ''
  ")

  # password hypervisor 1
  export hvpass${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][${i}-1]['password']
except:
 print ''
  ")

  # ip adress hypervisor 1
  export hvip${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][${i}-1]['url']
except:
 print ''
  " | cut -d/ -f3)
  done

  for i in 1 2 3 4 5 6 7 8 9
  do
    # username cs 1
    export cs${i}user=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['user']
except:
  print ''
")

    # password cs 1
    export cs${i}pass=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['passwd']
except:
 print ''
")

    # ip adress cs 1
    export cs${i}ip=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['mgtSvrIp']
except:
 print ''
")

    # hostname cs 1
    export cs${i}hostname=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['mgtSvrName']
except:
 print ''
")
  csip=
  eval csip="\$cs${i}ip"
  if [ -v $( eval "echo \${cs${i}ip}" ) ]  || [ "${csip}" == "localhost" ]; then
    if [ ! -v $( eval "echo \${cs${i}hostname}" ) ]; then
      eval cshostname="\$cs${i}hostname"
      export cs${i}ip=$(getent hosts ${cshostname} | awk '{ print $1 }')
    fi
  fi
  done
}

function cloud_conf_cosmic {
  # Configure the hostname properly - it doesn't exist if the deployeDB doesn't include devcloud
  # Insert OVS bridge
  # Garbage collector
  cloud_conf_generic

  # Adding the right SystemVMs, for both KVM and XenServer
  cloud_conf_templ_system
  # Adding the tiny linux VM templates for KVM and XenServer
  cloud_conf_templ_tinylinux
  # Make service offering support HA
  cloud_conf_offerings_ha
}

function cloud_conf_generic {
  # Configure the hostname properly - it doesn't exist if the deployeDB doesn't include devcloud
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '$host_ip') ON DUPLICATE KEY UPDATE value = '$host_ip';"
  # Insert OVS bridges
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'sdn.ovs.controller.default.label', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.private.network.device', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.public.network.device', 'pub0') ON DUPLICATE KEY UPDATE value = 'pub0';"
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.guest.network.device', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"
  # Garbage collector
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'network.gc.interval', '10') ON DUPLICATE KEY UPDATE value = '10';"
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'network.gc.wait', '10') ON DUPLICATE KEY UPDATE value = '10';"
  # Number of VPC tiers (as required by smoke/test_privategw_acl.py)
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'vpc.max.networks', '4') ON DUPLICATE KEY UPDATE value = '4';"
  # Force stop when destroying (makes it faster)
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'vm.destroy.forcestop', 'true') ON DUPLICATE KEY UPDATE value = 'true';"
}

function cloud_conf_templ_system {
  # Adding the right SystemVMs, for both KVM and XenServer
  echo "Config Templates"
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-xen.vhd.bz2' where id=1;"
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2' where id=3;"
}

function cloud_conf_templ_tinylinux {
  # Adding the tiny linux VM templates for KVM and XenServer
  echo "TinyLinux Templates"
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-kvm.qcow2.bz2', guest_os_id=140, name='tiny linux kvm', display_text='tiny linux kvm', hvm=1 where id=4;"
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2', guest_os_id=103, name='tiny linux xenserver', display_text='tiny linux xenserver', hvm=1 where id=2;"
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2', guest_os_id=103, name='tiny linux xenserver', display_text='tiny linux xenserver', hvm=1 where id=5;"
}

function cloud_conf_offerings_ha {
  # Make service offering support HA
  echo "Set all offerings to HA"
  mysql -u cloud -pcloud cloud --exec "UPDATE service_offering SET ha_enabled = 1;"
  mysql -u cloud -pcloud cloud --exec "UPDATE vm_instance SET ha_enabled = 1;"
}
