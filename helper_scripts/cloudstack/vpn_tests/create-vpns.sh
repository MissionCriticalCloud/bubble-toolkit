#!/bin/bash
#
#
#
vpncustgws=`cloudmonkey list vpncustomergateways | grep ^id | awk ' { print $3 }'`
vpngws=`cloudmonkey list vpngateways | grep ^id | awk ' { print $3 }'`
for vpngw in $vpngws
do
   pubip=`cloudmonkey list vpngateways id=$vpngw | grep ^publicip | awk '{print $3}'`
   echo "dealing with $vpngw, $pubip"
   for vpncustgw in $vpncustgws
   do
       custgw=`cloudmonkey list vpncustomergateways id=$vpncustgw | grep ^gateway | awk '{print $3}'`
       if [ $custgw == $pubip ]
       then
           echo "$pubip is me, $vpncustgw, $custgw, $vpngw!"
       else
           echo "creating vpn: $custgw, $pubip"
           cloudmonkey create vpnconnection s2scustomergatewayid=$vpncustgw s2svpngatewayid=$vpngw
       fi
   done
done
