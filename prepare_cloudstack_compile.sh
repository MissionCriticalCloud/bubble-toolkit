#!/bin/bash

# Script to prepare source for Apache CloudStack compile

# Get source
mkdir -p /data/git/$HOSTNAME
cd /data/git/$HOSTNAME
if [ ! -d "cloudstack/.git" ]; then
  echo "No git repo found, cloning Apache CloudStack"
  git clone https://github.com/apache/cloudstack.git
  echo "Please use 'git checkout' to checkout the branch you need."
else
  echo "Git Apache CloudStack repo already found"
fi
cd cloudstack

# Check VHD-UTIL
if [ ! -f "scripts/vm/hypervisor/xenserver/vhd-util" ]; then
  echo "Fetching vhd-util.."
  cd scripts/vm/hypervisor/xenserver
  wget http://download.cloud.com.s3.amazonaws.com/tools/vhd-util
  cd /data/git/$HOSTNAME/cloudstack
fi

# Set MVN compile options
export MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=512m -Xdebug -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=n -Djava.net.preferIPv4Stack=true"
pwd
echo "Done."
