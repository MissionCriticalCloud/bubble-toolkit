#!/bin/bash

# Prepare CentOS7 bare box to compile CloudStack and run management server
sleep 5
yum -y install maven tomcat mkisofs python-paramiko jakarta-commons-daemon-jsvc jsvc ws-commons-util genisoimage gcc python MySQL-python openssh-clients wget git python-ecdsa bzip2 python-setuptools mariadb-server mariadb python-devel vim nfs-utils screen setroubleshoot openssh-askpass java-1.8.0-openjdk-devel.x86_64 rpm-build rubygems nc
yum -y install http://mirror.karneval.cz/pub/linux/fedora/epel/epel-release-latest-7.noarch.rpm
yum --enablerepo=epel -y install sshpass mariadb

echo "max_allowed_packet=64M" >> /etc/my.cnf

systemctl start mariadb.service
systemctl enable mariadb.service
systemctl stop firewalld.service
systemctl disable firewalld.service

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

# Reboot
reboot

# Keep the script running unti reboot happens
while :
do
  # loop infinitely
done
