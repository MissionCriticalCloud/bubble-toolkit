#!/bin/bash

# We work from here
cd /data/git/$HOSTNAME/cloudstack
# Compile ACS
mvn clean install -P developer,systemvm -DskipTests
# Deploy DB
mvn -P developer -pl developer -Ddeploydb
# Configure the hostname properly - it doesn't exist if the deployeDB doesn't include devcloud
mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '`hostname`') ON DUPLICATE KEY UPDATE value = '`hostname`';"
# Get rid of CentOS 5 crap
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET unique_name='tiny Linux',name='tiny Linux',url='http://people.apache.org/~bhaisaab/vms/ttylinux_pv.vhd',checksum='046e134e642e6d344b34648223ba4bc1',display_text='tiny Linux' format='VHD', hypervisor_type='KVM'  where id=4;"

# Run mgt
mvn -pl :cloud-client-ui jetty:run
