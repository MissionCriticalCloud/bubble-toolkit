#!/bin/bash

#set -x
# set -e

start=$(date +"%s")
echo "Starting"

cloudmonkey sync
sod=""

zone_id=$(cloudmonkey list zones | grep ^id\ = | awk '{print $3}' | tail -1)
echo "Zone" $zone_id
templ=$(cloudmonkey list templates templatefilter=all keyword=tiny | grep ^id | awk ' { print $3 }')
if [ -z $templ ]
then
    templ=$(cloudmonkey list templates templatefilter=all zoneid=$zone_id | grep ^id | awk ' { print $3 }' | tail -1)
fi
# create two VMs
#
sod=$(cloudmonkey list serviceofferings keyword=small | grep ^id\ = |  awk '{ print $3 }' | tail -1)

networks=$(cloudmonkey list networks | grep ^id | awk ' { print $3 }' |  perl -ne 'chomp; print "$_ "')
mc=1
for net in $networks
do
    rest=$(cloudmonkey deploy virtualmachine zoneid=$zone_id name="VM${mc}" displayname="VM${mc}" templateid=$templ serviceofferingid=$sod networkids=$net)
    let mc=$mc+1
    echo $rest
done
end=$(date +"%s")
diff=$(($end-$start))
echo "Done in $(($diff / 60)) minutes and $(($diff % 60)) seconds."
