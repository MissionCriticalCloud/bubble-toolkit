#!/bin/bash

START=9
IPADDRESS="192.168.22."
MACADDR="52:54:00:1d:aa:"
CATEGORY="xen
kvm
ovm
net
prx
cs
db
sdn
gen
"

for c in $CATEGORY; do
  for n in $(seq 0 9); do
     START=$[$START+1]
     SUF=$(printf "%0.2x\n" $START)
     HOST=$c$n
     IP=$IPADDRESS$START
     MAC=$MACADDR$SUF
     echo "<host mac='$MAC' name='$HOST' ip='$IP'/>"
   done
done
