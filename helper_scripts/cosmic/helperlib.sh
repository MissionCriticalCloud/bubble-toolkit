#!/bin/sh

host_ip=`ip addr | grep 'inet 192' | cut -d: -f2 | awk '{ print $2 }' | awk -F\/24 '{ print $1 }'`

function install_kvm_packages {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3
  hasNsxDevice=$4

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
  if [ "$hasNsxDevice" == "True" ]; then
    ${ssh_base} ${hvuser}@${hvip} 'echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cosmic/agent/agent.properties'
    ${ssh_base} ${hvuser}@${hvip} 'echo "network.bridge.type=openvswitch" >> /etc/cosmic/agent/agent.properties'
    ${ssh_base} ${hvuser}@${hvip} 'echo "guest.cpu.mode=host-model" >> /etc/cosmic/agent/agent.properties'
  fi
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

  hasNsxDevice=$(cat ${marvinCfg} | grep -v "#" | python -c "
  try:
    import sys, json
    jsonObject = json.load(sys.stdin)
    niciraProviders = filter(lambda provider: provider['name'] == 'NiciraNvp', reduce(lambda a, b: a+b, map(lambda physical_net: physical_net['providers'], jsonObject['zones'][0]['physical_networks'])))
    if niciraProviders:
      print True
    else:
      print False
  except:
   print ERROR
  ")
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
  # Insert OVS bridge
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'sdn.ovs.controller.default.label', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"
  # Garbage collector
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'network.gc.interval', '60') ON DUPLICATE KEY UPDATE value = '60';"
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'network.gc.wait', '60') ON DUPLICATE KEY UPDATE value = '60';"
  # Number of VPC tiers (as required by smoke/test_privategw_acl.py)
  mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'vpc.max.networks', '4') ON DUPLICATE KEY UPDATE value = '4';"
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
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2', guest_os_id=140, name='tiny linux xenserver', display_text='tiny linux xenserver', hvm=1 where id=2;"
  mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2', guest_os_id=140, name='tiny linux xenserver', display_text='tiny linux xenserver', hvm=1 where id=5;"
}

function cloud_conf_offerings_ha {
  # Make service offering support HA
  echo "Set all offerings to HA"
  mysql -u cloud -pcloud cloud --exec "UPDATE service_offering SET ha_enabled = 1;"
  mysql -u cloud -pcloud cloud --exec "UPDATE vm_instance SET ha_enabled = 1;"
}
