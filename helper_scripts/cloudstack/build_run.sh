#!/bin/bash
cd /data/git/$HOSTNAME/cloudstack
mvn clean install -P developer,systemvm -DskipTests
mvn -P developer -pl developer -Ddeploydb
mvn -pl :cloud-client-ui jetty:run
