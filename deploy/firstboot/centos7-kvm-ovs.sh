#!/bin/bash

# Configure KVM POC Hypervisor (CentOS 7)
# Fred Neubauer / Remi Bergsma

# Genric KVM on Centos 7 setup
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
${DIR}/centos7-kvm-generic.sh


#### Networking #####
# Bring the second nic down to avoid routing problems
ip link set dev eth1 down

# BetaCloud pub vlan
VLANPUB=50
# VLANTRANS=13

# Bubble NSX Ctrl
NSXMANAGER="192.168.22.83"

### OVS ###
# Bridges
systemctl start openvswitch
echo "Creating bridges cloudbr0 and cloudbr1.."
ovs-vsctl add-br cloudbr0
ovs-vsctl add-br cloudbr1

# Get interfaces
IFACES=$(ls /sys/class/net | grep -E '^em|^eno|^eth|^p2' | tr '\n' ' ')

# Create Bond with them
echo "Creating bond with $IFACES"
#ovs-vsctl add-bond cloudbr0 bond0 $IFACES bond_mode=balance-tcp lacp=active other_config:lacp-time=fast
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
echo "Configuring cloubbr0"
echo "DEVICE=\"cloudbr0\"
ONBOOT=yes
DEVICETYPE=ovs
TYPE=OVSIntPort
BOOTPROTO=dhcp
HOTPLUG=no
MACADDR=$BRMAC
" > /etc/sysconfig/network-scripts/ifcfg-cloudbr0

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

# Set short hostname
hostnamectl --static set-hostname $(hostname --fqdn | cut -d. -f1)

# Cloudstack agent.properties settings
cp -pr /etc/cloudstack/agent/agent.properties /etc/cloudstack/agent/agent.properties.orig

# Add these settings (before adding the host)
echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cloudstack/agent/agent.properties
echo "network.bridge.type=openvswitch" >> /etc/cloudstack/agent/agent.properties
sed -i -e 's/\#vnc_listen.*$/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf

# Reboot
reboot
