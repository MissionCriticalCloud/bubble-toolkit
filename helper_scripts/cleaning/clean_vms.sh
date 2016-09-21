#!/usr/bin/env bash

for h in `virsh list --all | grep 'running\|shut off' | awk '{print $2}'`; do virsh destroy ${h}; virsh undefine ${h}; rm -f /data/images/${h}.img; done
