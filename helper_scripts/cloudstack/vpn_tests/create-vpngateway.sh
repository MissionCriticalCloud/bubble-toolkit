#!/bin/bash
#
#
#
vpcs=`cloudmonkey list vpcs enabled=true filter=id | grep -E ^id | awk ' { print $3 }'`
for vpc in $vpcs
do
   echo "Processing ${vpc}"
   vpngw=`cloudmonkey create vpngateway vpcid=$vpc`
done
