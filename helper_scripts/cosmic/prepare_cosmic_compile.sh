#!/bin/bash

# Script to prepare source for Cosmic compile

# Get source
BASEDIR=/data/git/${HOSTNAME}
MYDIR=$(pwd -P)
GITSSH=1
REPOURL=git@github.com:MissionCriticalCloud/cosmic.git

while getopts 'h' OPTION
do
  case $OPTION in
  h)    GITSSH=0
        ;;
  esac
done

function gitclone_cosmic {
  if [ "$GITSSH" -eq "1" ]; then
    git clone --recursive $REPOURL
  else
    git clone `echo $REPOURL | sed 's@git\@github.com:@https://github.com/@'`
    cd cosmic
    git submodule init
    sed -i 's@git\@github.com:@https://github.com/@' .git/config
    git submodule update
  fi
  echo "Please use 'git checkout' to checkout the branch you need."
}

function gitclone_packaging {
  if [ "$GITSSH" -eq "1" ]; then
    git clone --recursive git@github.com:MissionCriticalCloud/packaging.git packaging
  else
    git clone --recursive `echo git@github.com:MissionCriticalCloud/packaging.git | sed 's@git\@github.com:@https://github.com/@'` packaging
  fi
  echo "Please use 'git checkout' to checkout the branch you need."
}


mkdir -p ${BASEDIR}
cd ${BASEDIR}
if [ ! -d "cosmic/.git" ]; then
  echo "No git repo found, cloning Cosmic"
  gitclone_cosmic
else
  echo "Git Cosmic repo already found"
fi

if [ ! -d "packaging/.git" ]; then
  echo "No git repo found, cloning packaging"
  gitclone_packaging
else
  echo "Git packaging repo already found"
fi



COSMIC_BUILD_PATH=/data/git/$HOSTNAME/cosmic
cd $COSMIC_BUILD_PATH

# Check VHD-UTIL
if [ ! -f "cosmic-core/scripts/vm/hypervisor/xenserver/vhd-util" ]; then
  echo "Fetching vhd-util.."
  cd cosmic-core/scripts/vm/hypervisor/xenserver
  wget http://download.cloud.com.s3.amazonaws.com/tools/vhd-util
  cd $COSMIC_BUILD_PATH
fi

# Set MVN compile options
export MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=512m -Xdebug -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=n -Djava.net.preferIPv4Stack=true"
pwd
echo "Done."
