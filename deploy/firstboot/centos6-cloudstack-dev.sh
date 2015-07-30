#!/bin/bash

# Prepare CentOS6 box to install all dependencies of CloudStack and mount the storage
sleep 15
yum -y install mkisofs python-paramiko jakarta-commons-daemon-jsvc jsvc ws-commons-util genisoimage gcc python MySQL-python openssh-clients wget git bzip2 python-setuptools mysql mysql-server python-devel vim nfs-utils screen setroubleshoot openssh-askpass java-1.8.0-openjdk-devel.x86_64 rpm-build

# Installing Tomcat 7
wget http://www.us.apache.org/dist/tomcat/tomcat-7/v7.0.63/bin/apache-tomcat-7.0.63.tar.gz
tar xzf apache-tomcat-7.0.63.tar.gz
mv apache-tomcat-7.0.63 /usr/local/tomcat7

# We are not starting it yet
#cd /usr/local/tomcat7
#./bin/startup.sh

# Installing Maven3
wget http://mirror.cc.columbia.edu/pub/software/apache/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz
tar xzf apache-maven-3.3.3-bin.tar.gz
mv apache-maven-3.3.3 /usr/local/maven

# Add exports to profile and execute it
echo "export M2_HOME=/usr/local/maven" > /etc/profile.d/maven.sh
echo "export PATH=/usr/local/maven/bin:${PATH}" >> /etc/profile.d/maven.sh

service mysqld start

mkdir -p /data
mount -t nfs 192.168.22.1:/data /data
echo "192.168.22.1:/data /data nfs rw,hard,intr,rsize=8192,wsize=8192,timeo=14 0 0" >> /etc/fstab

mkdir -p /data/git
cd /data/git
cd /root

wget https://raw.githubusercontent.com/remibergsma/dotfiles/master/.screenrc

curl "https://bootstrap.pypa.io/get-pip.py" | python 
pip install mysql-connector-python --allow-external mysql-connector-python requests
pip install cloudmonkey

easy_install nose
easy_install pycrypto
