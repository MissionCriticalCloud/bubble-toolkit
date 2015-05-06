#!/bin/bash

# Fix hostname and uuid after deploying Xenserver 6.2 
echo "sleep 5; xe host-param-set uuid=$(xe host-list params=uuid|awk {'print $5'}) name-label=\$HOSTNAME">>/etc/rc.local
reboot
