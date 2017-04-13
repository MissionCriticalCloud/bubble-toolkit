#!/bin/bash

# Prepare CentOS6 box to install all dependencies of CloudStack and mount the storage
sleep 25
# Any packages should go to the Packer build

# Installing Maven3
wget http://ftp.nluug.nl/internet/apache/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
tar xzf apache-maven-3.3.9-bin.tar.gz
mv apache-maven-3.3.9 /usr/local/maven

# Add exports to profile and execute it
echo "export M2_HOME=/usr/local/maven" > /etc/profile.d/maven.sh
echo "export PATH=/usr/local/maven/bin:${PATH}" >> /etc/profile.d/maven.sh

chkconfig mysqld on
service mysqld start
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"

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
