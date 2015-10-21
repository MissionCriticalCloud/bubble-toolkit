#!/bin/bash

# Disable selinux
setenforce permissive
sed -i "/SELINUX=enforcing/c\SELINUX=permissive" /etc/selinux/config

# Disable firewall
systemctl stop firewall
systemctl disable firewalld

# Install dependencies for KVM on Cloudstack
sleep 5
yum -y install http://mirror.karneval.cz/pub/linux/fedora/epel/epel-release-latest-7.noarch.rpm
yum -y install qemu-kvm libvirt libvirt-python net-tools bridge-utils vconfig setroubleshoot virt-top virt-manager openssh-askpass wget vim
yum -y install http://jenkins.buildacloud.org/job/package-centos7-master/lastSuccessfulBuild/artifact/dist/rpmbuild/RPMS/x86_64/cloudstack-common-4.6.0-SNAPSHOT.el7.centos.x86_64.rpm 
yum -y install http://jenkins.buildacloud.org/job/package-centos7-master/lastSuccessfulBuild/artifact/dist/rpmbuild/RPMS/x86_64/cloudstack-agent-4.6.0-SNAPSHOT.el7.centos.x86_64.rpm
yum --enablerepo=epel -y install sshpass

# Enable rpbind for NFS
systemctl enable rpcbind
systemctl start rpcbind

# NFS to mct box
mkdir -p /data
mount -t nfs 192.168.22.1:/data /data
echo "192.168.22.1:/data /data nfs rw,hard,intr,rsize=8192,wsize=8192,timeo=14 0 0" >> /etc/fstab

# Enable nesting
echo "options kvm_intel nested=1" >> /etc/modprobe.d/kvm-nested.conf

# Cloudstack agent.properties settings
cp -pr /etc/cloudstack/agent/agent.properties /etc/cloudstack/agent/agent.properties.orig
# Add these settings (before adding the host)
# libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver
# network.bridge.type=openvswitch
#echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cloudstack/agent/agent.properties
#echo "network.bridge.type=openvswitch" >> /etc/cloudstack/agent/agent.properties
echo "guest.cpu.mode=host-model" >> /etc/cloudstack/agent/agent.properties

# Set the logging to DEBUG
sed -i 's/INFO/DEBUG/g' /etc/cloudstack/agent/log4j-cloud.xml

# Libvirtd parameters for Cloudstack
echo 'listen_tls = 0' >> /etc/libvirt/libvirtd.conf
echo 'listen_tcp = 1' >> /etc/libvirt/libvirtd.conf
echo 'tcp_port = "16509"' >> /etc/libvirt/libvirtd.conf
echo 'mdns_adv = 0' >> /etc/libvirt/libvirtd.conf
echo 'auth_tcp = "none"' >> /etc/libvirt/libvirtd.conf

# qemu.conf parameters for Cloudstack
sed -i -e 's/\#vnc_listen.*$/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf

# Create new initrd to disable co-mounts
sed -i "/JoinControllers/c\JoinControllers=''" /etc/systemd/system.conf
new-kernel-pkg --mkinitrd --install `uname -r`

# Network
# Device
echo "DEVICE=eth0
ONBOOT=yes
HOTPLUG=no
BOOTPROTO=none
TYPE=Ethernet
BRIDGE=cloudbr0" > /etc/sysconfig/network-scripts/ifcfg-eth0

# Pub
echo "DEVICE=cloudbr0.50
ONBOOT=yes
HOTPLUG=no
BOOTPROTO=none
VLAN=yes" > /etc/sysconfig/network-scripts/ifcfg-cloudbr0.50

# Bridge0
echo "DEVICE=cloudbr0
TYPE=Bridge
ONBOOT=yes
BOOTPROTO=dhcp
IPV6INIT=no
IPV6_AUTOCONF=no
DELAY=5
STP=yes" > /etc/sysconfig/network-scripts/ifcfg-cloudbr0

# Bridge1
echo "DEVICE=cloudbr1
TYPE=Bridge
ONBOOT=yes
BOOTPROTO=none
IPV6INIT=no
IPV6_AUTOCONF=no
DELAY=5
STP=yes" > /etc/sysconfig/network-scripts/ifcfg-cloudbr1

# Reboot
reboot

# Keep the script running until the reboot happens
while :
do
  # loop infinitely
done
