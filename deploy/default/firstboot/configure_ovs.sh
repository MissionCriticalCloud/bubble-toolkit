#!/bin/bash

# Bubble NSX Ctrl
NSXMANAGER="192.168.22.83"

# PUBLIC VLAN
VLANPUB=50

# Bridges
echo "Creating bridge cloudbr0.."
ovs-vsctl add-br cloudbr0
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

# NSX
echo "Point manager to NSX controller"
ovs-vsctl set-manager ssl:$NSXMANAGER:6632

### End OVS ###

