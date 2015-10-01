#!/bin/bash

# Check if a marvin dc file was specified
marvinCfg=$1
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  exit 1
fi

# Skip compile parameter
skip=$2

# Find ip
host_ip=`ip addr | grep 'inet 192' | cut -d: -f2 | awk '{ print $2 }' | awk -F\/24 '{ print $1 }'`

# We work from here
cd /data/git/$HOSTNAME/cloudstack

# Compile ACS
if [ -z ${skip} ]; then
  mvn clean install -P developer,systemvm -DskipTests
fi

# Deploy DB
mvn -P developer -pl developer -Ddeploydb

# Configure the hostname properly - it doesn't exist if the deployeDB doesn't include devcloud
mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '$host_ip') ON DUPLICATE KEY UPDATE value = '$host_ip';"
# Insert OVS bridge
mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'sdn.ovs.controller.default.label', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"

# Adding the right SystemVMs, for both KVM and Xen
# Adding the tiny linux VM templates for KVM and Xen
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

# Run mgt
echo "Starting CloudStack"
mvn -pl :cloud-client-ui jetty:run > jetty.log 2>&1 &

# Wait until it comes up
echo "Waiting for CloudStack to start"
while ! timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8096' 2>&1 > /dev/null; do sleep 10; done

# Zone name
zone=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['name']
")

# Hypervisor
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

