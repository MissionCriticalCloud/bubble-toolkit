#!/bin/bash
# Configure KVM Hypervisor with openvswitch and VXLAN (CentOS 7)
set -x
#
# Please install packages with the packer build: https://github.com/MissionCriticalCloud/bubble-templates-packer
#

# Bring the second nic down to avoid routing problems
ip link set dev eth1 down

# Disable selinux (for now...)
setenforce permissive
sed -i "/SELINUX=enforcing/c\SELINUX=permissive" /etc/selinux/config

# Disable firewall (for now..)
systemctl stop firewall
systemctl disable firewall

# FIXME
sleep 5

# Work-around situation where there is no ip address during firstboot
dhclient -v eth0

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
sed -i 's/#LIBVIRTD_ARGS/LIBVIRTD_ARGS/g' /etc/sysconfig/libvirtd

# qemu.conf parameters
sed -i -e 's/\#vnc_listen.*$/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf

### OVS ###
yum install -y yum-utils
yum-config-manager --enablerepo=extras
yum install -y centos-release-openstack-train
yum install -y openvswitch
yum install -y centos-release-qemu-ev
yum update -y

# Start and enable OVS
systemctl enable openvswitch
systemctl start openvswitch

# Execute OVS commands on reboot
cat /data/shared/deploy/default/firstboot/configure_ovs.sh >> /etc/rc.d/rc.local
echo "chmod 644 /etc/rc.d/rc.local" >> /etc/rc.d/rc.local
echo "sync; sleep1" >> /etc/rc.d/rc.local
echo "/usr/sbin/reboot" >> /etc/rc.d/rc.local

# Run this once
chmod 755  /etc/rc.d/rc.local

ifup cloudbr0

timedatectl set-timezone CET

cat > /root/.bash_history <<EOL
systemctl restart cosmic-agent
less /var/log/cosmic/agent/agent.log
EOL

cat > /root/.ssh/config <<EOL
Host 169.254.*
    Port 3922
    IdentityFile /root/.ssh/id_rsa.cloud
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
EOL

# Localstorage setup
pvcreate /dev/vdb
pvcreate /dev/vdc

vgcreate vg_vdb /dev/vdb
vgcreate vg_vdc /dev/vdc

# Reboot
echo "Syncing filesystems, will reboot soon.."
sync
sleep 2
echo "b" > /proc/sysrq-trigger
