#!/bin/bash

# some vars
zone_id=$(cloudmonkey list zones filter=id | grep -E ^id | awk {'print $3'} | head -n 1)
serviceoffering_id=$(cloudmonkey  list vpcofferings name="Default VPC offering" filter=id | grep -E ^id | awk {'print $3'})
domain_id=$(cloudmonkey list domains name=ROOT filter=id | grep -E ^id | awk {'print $3'} | head -n 1)
count=0
vpcs=2

while [ ${count} -lt ${vpcs} ]
do
  count=$[${count}+1]
  cidr="10.0.${count}.0/24"
  vpc_name="VPC${count}"
  acl_id=$(cloudmonkey list networkacllists name=default_allow filter=id | grep -E ^id | awk {'print $3'})
  net_id=$(cloudmonkey list networkofferings forvpc=true filter=id,name name=DefaultIsolatedNetworkOfferingForVpcNetworksWithInternalLB | grep -E ^id | awk {'print $3'})

  # create vpc
  vpc_id=$(cloudmonkey create vpc vpcofferingid=$serviceoffering_id zoneid=$zone_id name="${vpc_name}" displaytext="${vpc_name}" cidr="${cidr}" | grep ^id\ = | awk '{ print $3 }' &)

  # create tier
  network_id=$(cloudmonkey create network aclid=$acl_id displaytext="Tier ${vpc_name}" domainid=$domain_id gateway=10.0.${count}.1 netmask=255.255.255.0 name="Tier ${vpc_name}" networkofferingid=$net_id vpcid=$vpc_id zoneid=$zone_id)

done

