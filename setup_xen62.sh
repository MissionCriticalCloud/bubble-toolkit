#!/bin/bash

# Script to fix hostname and uuid after deploying Xenserver 6.2
service xapi stop

# Generate new uuid for both the host and dom0
sed -i "/INSTALLATION_UUID/c\INSTALLATION_UUID='$(uuidgen)'" /etc/xensource-inventory
sed -i "/CONTROL_DOMAIN_UUID/c\CONTROL_DOMAIN_UUID='$(uuidgen)'" /etc/xensource-inventory

# Get rid of the current state db
rm -rf  /var/xapi/state.db
service xapi start

# This is our fix script
cat <<EOT >> /etc/rc.local.fix
# Remove us from rc.local
sed -i '/local.fix/d' /etc/rc.local
# Set the hostname
sleep 5
xe host-param-set uuid=\$(xe host-list params=uuid|awk {'print \$5'} | head -n 1) name-label=\$HOSTNAME
reboot
EOT

# On the next boot, exec our fix script
echo "sh /etc/rc.local.fix >> /var/log/rc.local.fix 2>&1" >> /etc/rc.local

# More fixes
sleep 10
/opt/xensource/libexec/create_templates
echo yes | /opt/xensource/bin/xe-reset-networking --device=eth0 --mode=dhcp
sleep 20
reboot
