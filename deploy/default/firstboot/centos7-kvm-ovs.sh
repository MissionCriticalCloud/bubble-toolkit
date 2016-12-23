#!/bin/bash
# Configure KVM Hypervisor with openvswitch and STT (CentOS 7)
# Fred Neubauer / Remi Bergsma

# Disable mirrorlist in yum
sed -i '/mirrorlist/s/^/#/' /etc/yum.repos.d/*.repo
sed -i 's/#baseurl/baseurl/' /etc/yum.repos.d/*.repo

# Bring the second nic down to avoid routing problems
ip link set dev eth1 down

# Disable selinux (for now...)
setenforce permissive
sed -i "/SELINUX=enforcing/c\SELINUX=permissive" /etc/selinux/config

# Disable firewall (for now..)
systemctl stop firewall
systemctl disable firewalld

# Install dependencies for KVM
sleep 5
yum -y update
yum -y install epel-release python qemu-kvm qemu-img libvirt libvirt-python net-tools bridge-utils vconfig setroubleshoot virt-top virt-manager openssh-askpass openssh-clients wget vim socat java ebtables iptables ethtool iproute ipset perl
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

# Libvirtd parameters
echo 'listen_tls = 0' >> /etc/libvirt/libvirtd.conf
echo 'listen_tcp = 1' >> /etc/libvirt/libvirtd.conf
echo 'tcp_port = "16509"' >> /etc/libvirt/libvirtd.conf
echo 'mdns_adv = 0' >> /etc/libvirt/libvirtd.conf
echo 'auth_tcp = "none"' >> /etc/libvirt/libvirtd.conf

# qemu.conf parameters
sed -i -e 's/\#vnc_listen.*$/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf

### OVS ###
ADM_IP=
# Test to see if we have the internal mctadm1 box available
ping -c1 mctadm1 >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ADM_IP='mctadm1'
fi

## Check if 192.168.31.41 is available.
ping -c1 192.168.31.41 >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ADM_IP='192.168.31.41'
fi

# If mctadm1 is available, get OVS packages from it
if [ ! -v $( eval "echo \${ADM_IP}" ) ]
then
    echo "Detected we have an internal server to get OVS packages from."
    # Custom 2.6.2 with STT
    mv "/lib/modules/$(uname -r)/kernel/net/openvswitch/openvswitch.ko" "/lib/modules/$(uname -r)/kernel/net/openvswitch/openvswitch.org"
    yum -y install "kernel-devel-$(uname -r)"
    yum install -y dkms
    sed -i -e 's/srcversion:/srcversion.disabled:/' /usr/sbin/dkms
    yum -y install http://${ADM_IP}/openvswitch/openvswitch-dkms-2.6.2-1.el7.centos.x86_64.rpm
    yum -y install http://${ADM_IP}/openvswitch/openvswitch-2.6.2-1.el7.centos.x86_64.rpm
    dkms uninstall openvswitch/2.6.2
    dkms autoinstall openvswitch/2.6.2
    dkms status
# If not, fall back to community sources
else
    echo "Installing OVS from community sources."
    # Comunity 2.4.x
    yum install -y yum-utils
    yum-config-manager --enablerepo=extras
    yum install -y centos-release-openstack-mitaka
    yum install -y openvswitch
fi

# Start and enable OVS
systemctl enable openvswitch
systemctl start openvswitch

# Execute OVS commands on reboot
cat /data/shared/deploy/default/firstboot/configure_ovs.sh >> /etc/rc.d/rc.local
echo "chmod 644 /etc/rc.d/rc.local" >> /etc/rc.d/rc.local
echo "sync; sleep1" >> /etc/rc.d/rc.local
echo "echo b > /proc/sysrq-trigger" >> /etc/rc.d/rc.local

# Run this once
chmod 755  /etc/rc.d/rc.local

ifup cloudbr0

timedatectl set-timezone CET

# Reboot
echo "Syncing filesystems, will reboot soon.."
sync
sleep 2
echo "b" > /proc/sysrq-trigger
