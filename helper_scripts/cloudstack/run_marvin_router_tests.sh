#!/bin/bash

set -x

# Check if a marvin dc file was specified
marvinCfg=$1
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  exit 1
fi

# Go the the source
cd /data/git/${HOSTNAME}/cloudstack/test/integration

echo "Running tests with required_hardware=true"
nosetests --with-marvin --marvin-config=${marvinCfg} -s -a tags=advanced,required_hardware=true \
component/test_vpc_redundant.py \
component/test_routers_iptables_default_policy.py \
component/test_vpc_router_nics.py \
component/test_routers_network_ops.py 

echo "Running tests with required_hardware=false"
nosetests --with-marvin --marvin-config=${marvinCfg} -s -a tags=advanced,required_hardware=false \
smoke/test_routers.py \
smoke/test_network_acl.py \
smoke/test_privategw_acl.py \
smoke/test_reset_vm_on_reboot.py \
smoke/test_vm_life_cycle.py \
smoke/test_vpc_vpn.py \
smoke/test_service_offerings.py \
component/test_vpc_offerings.py \
component/test_vpc_routers.py

