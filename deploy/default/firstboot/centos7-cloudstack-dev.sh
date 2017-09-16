#!/bin/bash
# Prepare CentOS7 bare box to compile CloudStack and run management server
set -x
#
# Please install packages with the packer build: https://github.com/MissionCriticalCloud/bubble-templates-packer
#

# Centos 7.4 has stricter Selinux requirements
sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config

echo "JAVA_OPTS=\"-Djava.awt.headless=true -Dfile.encoding=UTF-8 -server -Xms1536m -Xmx3584m -XX:MaxPermSize=256M\"" >> ~tomcat/conf/tomcat.conf
systemctl restart tomcat.service

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
pip install cloudmonkey

easy_install nose
easy_install pycrypto

timedatectl set-timezone CET

# Reboot
reboot
