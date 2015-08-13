#!/bin/bash
#
#
#
policy="aes128-sha1"
dpd="True"
ipsecpsk="somekey"
exclude="test"
networks=`cloudmonkey list networks | grep ^id | awk ' { print $3 }'`

for net in $networks
do
   display=`cloudmonkey list networks id=$net | grep ^displaytext | awk '{ print $3 }'`
   if [ "$display" == "$exclude" ]
   then
       networks=`echo $networks | sed -e s/$net//`
   else
       cidr=`cloudmonkey list networks id=$net | grep ^cidr | awk '{ print $3 }'`
       name=`cloudmonkey list networks id=$net | grep ^name | awk '{ print $3 }' | head -1`
       gateway=`cloudmonkey list networks id=$net | grep ^gateway | awk '{ print $3 }'`
       vpcid=`cloudmonkey list networks id=$net | grep ^vpcid | awk '{ print $3 }'`
       pubip=`cloudmonkey list routers vpcid=$vpcid | grep ^publicip | awk '{ print $3 }'`
       key="${ipsecpsk}${name}"
       vpncustgw=`cloudmonkey create vpncustomergateway gateway=$pubip cidrlist=$cidr dpd=$dpd ipsecpsk=$key ikepolicy=$policy esppolicy=$policy name=VPN-${name}-${cidr}`
       echo $vpncustgw
   fi
done
