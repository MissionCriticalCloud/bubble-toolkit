#!/bin/bash

# We get this passed from the main script
NSX_CONTROLLER=$1
KVM_HOST=$2

KVM_HOST_IP=$(getent hosts ${KVM_HOST} | awk '{ print $1 }')

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${DIR}/post_detect_reboot.sh ${KVM_HOST}

# Wait for controller to be responding
while ! ping -c3 ${NSX_CONTROLLER} &>/dev/null; do
  sleep 2
done

SSH_OPTIONS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

echo "Note: Authenticating against controller"
curl -k -c cookie.txt -X POST -d 'username=admin&password=admin' https://${NSX_CONTROLLER}/ws.v1/login

echo "Note: waiting for controller to be ready"
while ! curl -sD - -k -b cookie.txt  https://${NSX_CONTROLLER}/ws.v1/control-cluster  | grep "HTTP/1.1 200"; do
  sleep 5
done

echo "Note: Retrieving Transport Zone"
curl -k -b cookie.txt https://${NSX_CONTROLLER}/ws.v1/transport-zone 2> /dev/null 1> transport-zone-list.json
# retrieve the transport zone uuid (to use further down the line)
transportZoneUuid="$(cat transport-zone-list.json | sed -e 's/^.*transport-zone\///' -e 's/".*$//')"

echo "Note: Getting KVM host certificate"
kvmOvsCertificate=$(sshpass -p 'password' ssh ${SSH_OPTIONS} root@${KVM_HOST} cat /etc/openvswitch/ovsclient-cert.pem | sed -z "s/\n/\\\\n/g")

echo "Note: Creating KVM host (${KVM_HOST}) Transport Connector in Zone with UUID = ${transportZoneUuid} "
curl -k -b cookie.txt -X POST -d '{
    "credential": {
        "client_certificate": {
            "pem_encoded": "'"${kvmOvsCertificate}"'"
        },
        "type": "SecurityCertificateCredential"
    },
    "display_name": "mct-'"${KVM_HOST}"'-node",
    "integration_bridge_id": "br-int",
    "transport_connectors": [
        {
            "ip_address": "'"${KVM_HOST_IP}"'",
            "transport_zone_uuid": "'"${transportZoneUuid}"'",
            "type": "STTConnector"
        }
    ]
}' https://${NSX_CONTROLLER}/ws.v1/transport-node 2> /dev/null 1> transport-node-${KVM_HOST}.json
