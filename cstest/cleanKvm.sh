#!/bin/sh

for host in $(virsh list | awk '{print $2;}' | grep -v Name |egrep -v '^$')
do
	virsh destroy $host
done
