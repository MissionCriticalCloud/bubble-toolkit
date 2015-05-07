#!/bin/bash

# Script to prepare source for Apache CloudStack compile

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

# Prepare the box so that it can build systemvm images

echo Installing tools to generate systemvm templates
yum install -y kernel-devel

cat << ORACLE_REPO > /etc/yum.repos.d/oracle.repo
[virtualbox]
name=Oracle Linux / RHEL / CentOS-$releasever / $basearch - VirtualBox
baseurl=http://download.virtualbox.org/virtualbox/rpm/el/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://www.virtualbox.org/download/oracle_vbox.asc
ORACLE_REPO

install_pkg VirtualBox-4.3 ruby ruby-devel gcc-c++ zlib-devel libxml2-devel patch sharutils genisoimage
gem install bundler
#cd ${BASEDIR}/tools/appliance
## bundle check || bundle install
SONAME=1
LIBS="${MYDIR}/faketime/libfaketime.so.${SONAME} ${MYDIR}/faketime/libfaketimeMT.so.${SONAME}"

install -dm0755 "/usr/local/lib/faketime"
install -m0644 ${LIBS} "/usr/local/lib/faketime"
install -Dm0755 ${MYDIR}/faketime/faketime "/usr/local/bin/faketime"

install -dm0755 "/usr/local/lib/vhd"
install -m0644 ${MYDIR}/vhd-util/libvhd.so.1.0 "/usr/local/lib/vhd"
install -Dm0755 ${MYDIR}/vhd-util/vhd-util "/usr/local/bin/vhd-util"
echo "/usr/local/lib/vhd" > /etc/ld.so.conf.d/vhd-util-x86_64.conf
ldconfig
echo All tools for systemvm generation installed
