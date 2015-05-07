#!/bin/bash

BASEDIR=/data/git/${HOSTNAME}

mkdir -p ${BASEDIR}
cd ${BASEDIR}

# Setup and clone
if [ ! -d "cloudstackOps/.git" ]; then
  git clone https://github.com/remibergsma/cloudstackOps.git
  cd cloudstackOps
  cp -pr config.sample config
else
  echo "CloudstackOps clone already available."
fi
if [ ! -d "${BASEDIR}/python_cloud" ]; then
  echo "Setting up virtualenv.."
  sudo yum -y install python-virtualenv
  virtualenv ${BASEDIR}/python_cloud
  pip install mysql-connector-python --allow-external mysql-connector-python requests
  pip install -Iv ${BASEDIR}/cloudstackOps/marvin/Marvin-0.1.0.tar.gz
  pip install prettytable clint
fi

# Feed API keys to CloudMonkey config
echo "Setting up API keys to ${BASEDIR}/cloudstackOps/config"
APIKEY=$(cloudmonkey list accounts name=admin | grep 'apikey' | awk {'print $3'})
SECRETKEY=$(cloudmonkey list accounts name=admin | grep 'secretkey' | awk {'print $3'})
sed -i "/apikey/c\apikey = $APIKEY" ${BASEDIR}/cloudstackOps/config
sed -i "/secretkey/c\secretkey = $SECRETKEY" ${BASEDIR}/cloudstackOps/config
sed -i "/url/c\url = http://cs1.cloud.lan:8080/client/api" ${BASEDIR}/cloudstackOps/config
echo "Done. To get started:"
echo
echo " virtualenv ${BASEDIR}/python_cloud" 
echo " cd ${BASEDIR}/cloudstackOps"
echo " python listVirtualMachines.py -o MCCT-XEN-1"

