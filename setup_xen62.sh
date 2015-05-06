#!/bin/bash

# Fix hostname and uuid after deploying Xenserver 6.2
sed -i "/INSTALLATION_UUID/c\INSTALLATION_UUID='$(uuidgen)'" /etc/xensource-inventory
sed -i "/CONTROL_DOMAIN_UUID/c\CONTROL_DOMAIN_UUID='$(uuidgen)'" /etc/xensource-inventory
rm -f /var/xapi/state.db
echo "sh /etc/rc.local.fix" >> /etc/rc.local

cat <<EOT >> /etc/rc.local.fix
sleep 5
xe host-param-set uuid=\$(xe host-list params=uuid|awk {'print \$5'}) name-label=\$HOSTNAME
PIFUUID=\$(xe pif-list params=uuid | awk {'print \$5'})
xe host-management-reconfigure pif-uuid=\$PIFUUID
xe pif-scan host-uuid=\$(xe host-list params=uuid|awk {'print \$5'})
xe pif-reconfigure-ip uuid=\$PIFUUID mode=dhcp
xe host-management-reconfigure pif-uuid=\$PIFUUID
xe host-forget uuid=$(xe host-list params=uuid|awk {'print $5'}) --force
rm /etc/rc.local.fix
sed -i '/local.fix/d' /etc/rc.local
EOT

reboot
