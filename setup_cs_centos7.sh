#!/bin/bash

# Prepare CentOS7 bare box to compile CloudStack and run management server

yum -y install maven tomcat6 mkisofs genisoimage gcc python MySQL-python openssh-clients wget git python-ecdsa bzip2 python-setuptools mariadb-server mariadb python-devel vim nfs-utils screen

systemctl start mariadb.service
systemctl enable mariadb.service
systemctl stop firewalld.service
systemctl disable firewalld.service

mkdir -p /data
mount -t nfs 192.168.22.1:/data /data

mkdir -p /data/git
cd /data/git
cd /root

wget https://raw.githubusercontent.com/remibergsma/dotfiles/master/.screenrc

curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
python get-pip.py
pip install mysql-connector-python --allow-external mysql-connector-python requests
