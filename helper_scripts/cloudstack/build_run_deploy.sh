#!/bin/bash

# This script builds and runs Apache CloudStack and deploys a data center using the supplied Marvin config.
# When KVM is used, RPMs are built and installed on the hypervisor.
# When done, you may run the desired tests.

# Check if a marvin dc file was specified
marvinCfg=$1
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  exit 1
fi

# Parameter to skip compilation
skip=$2

# Find ip
host_ip=`ip addr | grep 'inet 192' | cut -d: -f2 | awk '{ print $2 }' | awk -F\/24 '{ print $1 }'`

# We work from here
cd /data/git/$HOSTNAME/cloudstack

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

# SSH/SCP helpers
ssh_base="sshpass -p ${hvpass1} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
scp_base="sshpass -p ${hvpass1} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

# Compile CloudStack
if [ -z ${skip} ]; then

  # Compile RPM packages for KVM hypervisor
  # When something VR related is changed, one must use the RPMs from the branch we're testing
  if [[ "$hypervisor" == "kvm" ]]; then
    echo "Creating rpm packages for ${hypervisor}"
    cd packaging
    # CentOS7 is hardcoded for now
    ./package.sh -d centos7

    # scp packages to hypervisor, remove existing, then install new ones
    ${ssh_base} ${hvuser1}@${hvip1} rm cloudstack-*
    ${scp_base} ../dist/rpmbuild/RPMS/x86_64/* ${hvuser1}@${hvip1}:
    ${ssh_base} ${hvuser1}@${hvip1} yum -y remove cloudstack-common
    ${ssh_base} ${hvuser1}@${hvip1} yum -y localinstall cloudstack-agent* cloudstack-common*

    # Do we have a second hypervisor
    if [ ! -z  ${hvip2} ]; then
      ${ssh_base} ${hvuser2}@${hvip2} rm cloudstack-*
      ${scp_base} ../dist/rpmbuild/RPMS/x86_64/* ${hvuser2}@${hvip2}:
      ${ssh_base} ${hvuser2}@${hvip2} yum -y remove cloudstack-common
      ${ssh_base} ${hvuser2}@${hvip2} yum -y localinstall cloudstack-agent* cloudstack-common*
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
  mvn ${clean} install -P developer,systemvm -DskipTests
fi

# Deploy DB
echo "Deploying CloudStack DB"
mvn -P developer -pl developer -Ddeploydb

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
echo "Starting CloudStack"
killall -9 java
mvn -pl :cloud-client-ui jetty:run > jetty.log 2>&1 &

# Wait until it comes up
echo "Waiting for CloudStack to start"
while ! timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do sleep 10; done

# Systemvm template for hypervisor type
if [[ "${hypervisor}" == "kvm" ]]; then
  systemvmurl="http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2"
  imagetype="qcow2"
 elif [[ "${hypervisor}" == "xenserver" ]]; then
  systemvmurl="http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-xen.vhd.bz2"
  imagetype="vhd"
fi 

echo "Install systemvm template.."
bash -x ./scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondarystorage} -u ${systemvmurl} -h ${hypervisor} -o localhost -r root -e ${imagetype} -F

echo "Deploy data center.."
python /data/git/$HOSTNAME/cloudstack/tools/marvin/marvin/deployDataCenter.py -i ${marvinCfg}

# We may want to run some tests here
