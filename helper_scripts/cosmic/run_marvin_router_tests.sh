#!/bin/bash

set -x

# Check if a marvin dc file was specified
marvinCfg=$1
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  exit 1
fi

COSMIC_BUILD_PATH=/data/git/$HOSTNAME/cosmic
COSMIC_RUN_PATH=$COSMIC_BUILD_PATH/cosmic-core

# Go the the source
cd $COSMIC_RUN_PATH/test/integration

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
