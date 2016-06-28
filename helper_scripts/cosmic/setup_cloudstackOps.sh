#!/bin/bash

BASEDIR=/data/git/${HOSTNAME}

mkdir -p ${BASEDIR}
cd ${BASEDIR}

# Setup and clone
if [ ! -d "cloudstackOps/.git" ]; then
  git clone https://github.com/schubergphilis/cloudstackOps.git
  cd cloudstackOps
  cp -pr config.sample config
else
  echo "CloudstackOps clone already available."
fi
if [ ! -d "${BASEDIR}/python_cloud" ]; then
  echo "Setting up virtualenv.."
  sudo yum -y install python-virtualenv
  virtualenv ${BASEDIR}/python_cloud
  source ${BASEDIR}/python_cloud/bin/activate
  pip install --extra-index-url https://pypi.python.org/pypi/mysql-connector-python/2.0.4 mysql-connector-python
  pip install ${BASEDIR}/cloudstackOps/marvin/Marvin-0.1.0.tar.gz
  pip install prettytable clint
fi

# Feed API keys to CloudMonkey config
echo "Setting up API keys to ${BASEDIR}/cloudstackOps/config"
cloudmonkey set display default
APIKEY=$(cloudmonkey list accounts name=admin | grep 'apikey' | awk {'print $3'})
SECRETKEY=$(cloudmonkey list accounts name=admin | grep 'secretkey' | awk {'print $3'})
sed -i "/apikey/c\apikey = $APIKEY" ${BASEDIR}/cloudstackOps/config
sed -i "/secretkey/c\secretkey = $SECRETKEY" ${BASEDIR}/cloudstackOps/config
sed -i "/url/c\url = http://cs1.cloud.lan:8080/client/api" ${BASEDIR}/cloudstackOps/config
echo "Done. To get started:"
echo
echo " source ${BASEDIR}/python_cloud/bin/activate" 
echo " cd ${BASEDIR}/cloudstackOps"
echo " python listVirtualMachines.py -o MCCT-XEN-1"
