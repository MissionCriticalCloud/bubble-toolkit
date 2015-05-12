#!/bin/bash
#
# Yury V. Zaytsev <yury@shurup.com> (C) 2011
#
# This work is herewith placed in public domain.
#
# Use this script to cleanly restart the default libvirt network after its
# definition have been changed (e.g. added new static MAC+IP mappings) in order
# for the changes to take effect. Restarting the network alone, however, causes
# the guests to lose connectivity with the host until their network interfaces
# are re-attached.
#
# The script re-attaches the interfaces by obtaining the information about them
# from the current libvirt definitions. It has the following dependencies:
#
#   - virsh (obviously)
#   - tail / head / grep / awk / cut
#   - XML::XPath (e.g. perl-XML-XPath package)
#
# Note that it assumes that the guests have exactly 1 NAC each attached to the
# given network! Extensions to account for more (or none) interfaces etc. are,
# of course, most welcome.
#
# ZYV
#

set -e
set -u

NETWORK_NAME=virbr0
MACHINES=$( virsh list | tail -n +3 | head -n -1 | awk '{ print $2; }' )
MACHINES='xen4'

for m in $MACHINES ; do

    echo "$m"
    MACHINE_INFO=$( virsh dumpxml "$m" | xpath /domain/devices/interface[1] 2> /dev/null )

    echo "$MACHINE_INFO"
    MACHINE_MAC=$( echo "$MACHINE_INFO" | grep "mac address" | cut -d '"' -f 2 )

    echo "$MACHINE_MAC"
    MACHINE_MOD=$( echo "$MACHINE_INFO" | grep "model type" | cut -d '"' -f 2 )

    set +e
    virsh detach-interface "$m" bridge --mac "$MACHINE_MAC" && sleep 3
    virsh attach-interface "$m" bridge $NETWORK_NAME --mac "$MACHINE_MAC" --model "$MACHINE_MOD"
    set -e

done
