#!/bin/bash

# We work from here
cd /data/git/$HOSTNAME/cloudstack
# Compile ACS
mvn clean install -P developer,systemvm -DskipTests
# Deploy DB
mvn -P developer -pl developer -Ddeploydb
# Get rid of CentOS 5 crap
mysql -u cloud -pcloud cloud --exec "DELETE from vm_template where type=\"BUILTIN\";"
mysql -u cloud -pcloud cloud --exec "UPDATE cloud.configuration SET value='`hostname`' WHERE name='host';"
# Run mgt
mvn -pl :cloud-client-ui jetty:run
