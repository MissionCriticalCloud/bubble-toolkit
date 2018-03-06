#!/bin/bash
. `dirname $0`/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  echo "This script prepares the required infrastructure for integration tests, based on a marvin configuration file"
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

# Options
cloudstack_deploy_mode=0
while getopts 'cm:' OPTION
do
  case $OPTION in
  m)    marvin_config="$OPTARG"
        ;;
  c)    cloudstack_deploy_mode=1
        ;;
  esac
done

say "Received arguments:"
say "marvin_config = ${marvin_config}"

# Check if a marvin dc file was specified
if [ -z ${marvin_config} ]; then
  say "No Marvin config specified. Quiting."
  usage
  exit 1
else
  say "Using Marvin config '${marvin_config}'."
fi

if [ ! -f "${marvin_config}" ]; then
    say "Supplied Marvin config not found!"
    exit 1
fi

parse_marvin_config ${marvin_config}

mkdir -p ${primarystorage}

# CloudStack flag
CLOUDSTACKFLAG=""
if [ ${cloudstack_deploy_mode} -eq 1 ]; then
  CLOUDSTACKFLAG="--cloudstack"
fi

if [ ${hypervisor} = "kvm" ]; then
  say "Found hypervisor: ${hypervisor}; changing MTU to 1600"
  for h in `ls /sys/devices/virtual/net/virbr0/brif/`; do sudo /usr/sbin/ip link set dev ${h} mtu 1600; done
  sudo /usr/sbin/ip link set dev virbr0 mtu 1600
  sudo /usr/sbin/ip link set dev virbr0.50 mtu 1600
fi
if [ ${hypervisor} = "xenserver" ]; then
  say "Found hypervisor: ${hypervisor}; changing MTU to 1500"
  for h in `ls /sys/devices/virtual/net/virbr0/brif/`; do sudo /usr/sbin/ip link set dev ${h} mtu 1500; done
  sudo /usr/sbin/ip link set dev virbr0 mtu 1500
  sudo /usr/sbin/ip link set dev virbr0.50 mtu 1500
fi

# Make sure bridge is up
sudo /usr/sbin/ifup virbr0.50

say "Creating hosts"
/data/shared/deploy/kvm_local_deploy.py -m ${marvin_config} --force ${CLOUDSTACKFLAG} 2>&1
