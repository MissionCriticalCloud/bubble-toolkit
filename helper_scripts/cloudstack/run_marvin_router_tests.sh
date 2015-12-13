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
smoke/test_password_server.py \
smoke/test_vpc_redundant.py \
smoke/test_routers_iptables_default_policy.py \
smoke/test_routers_network_ops.py \
smoke/test_vpc_router_nics.py \
smoke/test_router_dhcphosts.py \
smoke/test_loadbalance.py \
smoke/test_internal_lb.py \
smoke/test_ssvm.py \
smoke/test_vpc_vpn.py \
smoke/test_privategw_acl.py \
smoke/test_network.py


echo "Running tests with required_hardware=false"
nosetests --with-marvin --marvin-config=${marvinCfg} -s -a tags=advanced,required_hardware=false \
smoke/test_routers.py \
smoke/test_network_acl.py \
smoke/test_reset_vm_on_reboot.py \
smoke/test_vm_life_cycle.py \
smoke/test_service_offerings.py \
smoke/test_network.py \
component/test_vpc_offerings.py \
component/test_vpc_routers.py

