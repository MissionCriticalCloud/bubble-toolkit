#!/bin/bash

# Script to prepare source for Cosmic compile

# Get source
BASEDIR=/data/git/${HOSTNAME}
MYDIR=$(pwd -P)

install_pkg() {
	NAME=$*
	yum install -y ${NAME}
	if [ "$?" -ne "0" ]
	then
		echo Package Installation Failed exiting
		exit 1
	fi
}

mkdir -p ${BASEDIR}
cd ${BASEDIR}
if [ ! -d "cosmic/.git" ]; then
  echo "No git repo found, cloning Cosmic"
  git clone --recursive git@github.com:MissionCriticalCloud/cosmic.git
  echo "Please use 'git checkout' to checkout the branch you need."
else
  echo "Git Cosmic repo already found"
fi

if [ ! -d "cosmic/packaging/.git" ]; then
  echo "No git repo found, cloning packaging"
  git clone --recursive git@github.com:MissionCriticalCloud/packaging.git cosmic/packaging
  echo "Please use 'git checkout' to checkout the branch you need."
else
  echo "Git packaging repo already found"
fi



COSMIC_BUILD_PATH=/data/git/$HOSTNAME/cosmic
cd $COSMIC_BUILD_PATH

# Check VHD-UTIL
if [ ! -f "scripts/vm/hypervisor/xenserver/vhd-util" ]; then
  echo "Fetching vhd-util.."
  cd cosmic-core/scripts/vm/hypervisor/xenserver
  wget http://download.cloud.com.s3.amazonaws.com/tools/vhd-util
  cd $COSMIC_BUILD_PATH
fi

# Set MVN compile options
export MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=512m -Xdebug -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=n -Djava.net.preferIPv4Stack=true"
pwd
echo "Done."
