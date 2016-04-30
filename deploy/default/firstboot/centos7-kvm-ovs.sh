#!/bin/bash
# Configure KVM Hypervisor with openvswitch and STT (CentOS 7)
# Fred Neubauer / Remi Bergsma

# Disable mirrorlist in yum
sed -i '/mirrorlist/s/^/#/' /etc/yum.repos.d/*.repo
sed -i 's/#baseurl/baseurl/' /etc/yum.repos.d/*.repo

# Bring the second nic down to avoid routing problems
ip link set dev eth1 down

### Settings ####
VLANPUB=50

# Bubble NSX Ctrl
NSXMANAGER="192.168.22.83"

# Disable selinux (for now...)
setenforce permissive
sed -i "/SELINUX=enforcing/c\SELINUX=permissive" /etc/selinux/config

# Disable firewall (for now..)
systemctl stop firewall
systemctl disable firewalld

# Install dependencies for KVM
sleep 5
yum -y install epel-release qemu-kvm libvirt libvirt-python net-tools bridge-utils vconfig setroubleshoot virt-top virt-manager openssh-askpass wget vim socat
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
# Test to see if we have the internal mctadm1 box available
ping -c1 mctadm1 >/dev/null 2>&1
MCTADM1_AVAILABLE=$?

# If mctadm1 is available, get OVS packages from it
if [ ${MCTADM1_AVAILABLE} -eq 0 ]
  then
  echo "Detected we have server mctadm1 to get OVS packages from."
  # Custom 2.5.1
  mv "/lib/modules/$(uname -r)/kernel/net/openvswitch/openvswitch.ko" "/lib/modules/$(uname -r)/kernel/net/openvswitch/openvswitch.org"
  yum -y install "kernel-devel-$(uname -r)"
  yum -y install http://mctadm1/openvswitch/openvswitch-dkms-2.5.1-1.el7.centos.x86_64.rpm
  yum -y install http://mctadm1/openvswitch/openvswitch-2.5.1-1.el7.centos.x86_64.rpm
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

# Bridges
systemctl start openvswitch
echo "Creating bridges cloudbr0 and cloudbr1.."
ovs-vsctl add-br cloudbr0
ovs-vsctl add-br cloudbr1
ovs-vsctl add-br cloud0

# Get interfaces
IFACES=$(ls /sys/class/net | grep -E '^em|^eno|^eth|^p2' | tr '\n' ' ')

# Create Bond with them
echo "Creating bond with $IFACES"
ovs-vsctl add-bond cloudbr0 bond0 $IFACES

# Integration bridge
echo "Creating NVP integration bridge br-int"
ovs-vsctl -- --may-exist add-br br-int\
            -- br-set-external-id br-int bridge-id br-int\
            -- set bridge br-int other-config:disable-in-band=true\
            -- set bridge br-int fail-mode=secure

# Fake bridges
echo "Create fake bridges"
#ovs-vsctl -- add-br trans0 cloudbr0 $VLANTRANS
ovs-vsctl -- add-br trans0 cloudbr0
ovs-vsctl -- add-br pub0 cloudbr0 $VLANPUB

# Network configs
BRMAC=$(cat /sys/class/net/$(ls /sys/class/net | grep -E '^em|^eno|^eth|^p2' | tr '\n' ' ' | awk {'print $1'})/address)

# Physical interfaces
for i in $IFACES
  do echo "Configuring $i..."
  echo "DEVICE=$i
ONBOOT=yes
NETBOOT=yes
IPV6INIT=no
BOOTPROTO=none
NM_CONTROLLED=no
" > /etc/sysconfig/network-scripts/ifcfg-$i
done

# Config cloudbr0
echo "Configuring cloudbr0"
echo "DEVICE=\"cloudbr0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSBridge
BOOTPROTO=dhcp
HOTPLUG=no
MACADDR=$BRMAC
" > /etc/sysconfig/network-scripts/ifcfg-cloudbr0

# Config cloud0
echo "Configuring cloud0"
echo "DEVICE=\"cloud0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSBridge
IPADDR=169.254.0.1
NETMASK=255.255.0.0
BOOTPROTO=static
HOTPLUG=no
" > /etc/sysconfig/network-scripts/ifcfg-cloud0

# Config trans0
echo "Configuring trans0"
echo "DEVICE=\"trans0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSIntPort
BOOTPROTO=dhcp
HOTPLUG=no
#MACADDR=$BRMAC
" > /etc/sysconfig/network-scripts/ifcfg-trans0

# Config bond0
echo "Configuring bond0"
echo "DEVICE=\"bond0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSBond
OVS_BRIDGE=cloudbr0
BOOTPROTO=none
BOND_IFACES=\"$IFACES\"
#OVS_OPTIONS="bond_mode=balance-tcp lacp=active other_config:lacp-time=fast"
HOTPLUG=no
" > /etc/sysconfig/network-scripts/ifcfg-bond0

echo "Generate OVS certificates"
cd /etc/openvswitch
ovs-pki req ovsclient
ovs-pki self-sign ovsclient
ovs-vsctl -- --bootstrap set-ssl \
            "/etc/openvswitch/ovsclient-privkey.pem" "/etc/openvswitch/ovsclient-cert.pem"  \
            /etc/openvswitch/vswitchd.cacert

# NSX
echo "Point manager to NSX controller"
ovs-vsctl set-manager ssl:$NSXMANAGER:6632

### End OVS ###
ifup cloudbr0

timedatectl set-timezone CET

# Reboot
reboot
