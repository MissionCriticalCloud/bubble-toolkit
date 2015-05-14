#!/bin/bash

cloudmonkey set table default
TEMPOSID=$(cloudmonkey list ostypes keyword="Other PV (64-bit)" filter=id | grep ^id | awk {'print $3'})
# XenServer
cloudmonkey register template displayText=Tiny format=VHD hypervisor=XenServer isextractable=true isfeatured=true ispublic=true isrouting=false name=Tiny osTypeId=$TEMPOSID passwordEnabled=true requireshvm=true zoneid=-1 url=http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2
# KVM
cloudmonkey register template displayText=Tiny format=Qcow2 hypervisor=KVM isextractable=true isfeatured=true ispublic=true isrouting=false name=Tiny osTypeId=$TEMPOSID passwordEnabled=true requireshvm=true zoneid=-1 url=http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-kvm.qcow2.bz2
