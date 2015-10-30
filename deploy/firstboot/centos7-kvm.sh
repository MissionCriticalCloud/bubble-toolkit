#!/bin/bash

# Genric KVM on Centos 7 setup
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
${DIR}/centos7-kvm-generic.sh

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

