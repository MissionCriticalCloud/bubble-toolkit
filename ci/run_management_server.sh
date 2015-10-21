#!/bin/bash

set -e

cd /vagrant

mvn -P developer -pl developer -Ddeploydb
mvn -P developer -pl developer -Ddeploydb-simulator

mysql -u cloud -pcloud cloud --exec "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '$host_ip') ON DUPLICATE KEY UPDATE value = '$host_ip';"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET unique_name='tiny Linux KVM',name='tiny Linux',url='http://artifacts.schubergphilis.com/artifacts/cloudstack/mcct/tiny.qcow2',checksum='b6c1b60a55fe2e31afa32df10b342951', \
    display_text='tiny Linux KVM', format='QCOW2', hypervisor_type='KVM'  where id=4;"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.vm_template SET unique_name='tiny Linux Xen',name='tiny Linux',url='http://artifacts.schubergphilis.com/artifacts/cloudstack/tiny_vhd/ce5b212e-215a-3461-94fb-814a635b2215.vhd',checksum='046e134e642e6d344b34648223ba4bc1', \
    display_text='tiny Linux Xen', format='VHD', hypervisor_type='XernServer'  where id=5;"

MAVEN_OPTS="-Xmx2G" mvn -Dsimulator -pl :cloud-client-ui jetty:run -Djava.net.preferIPv4Stack=true
