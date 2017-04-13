#!/bin/bash

# We get this passed from the main script
NSX_MANAGER=$1
NSX_CONTROLLER=$2
NSX_SERVICE=$3
KVM_HOST=$4

NSX_CONTROLLER_IP=$(getent hosts ${NSX_CONTROLLER} | awk '{ print $1 }')
NSX_SERVICE_IP=$(getent hosts ${NSX_SERVICE} | awk '{ print $1 }')
KVM_HOST_IP=$(getent hosts ${KVM_HOST} | awk '{ print $1 }')

# Wait for controller to be responding
while ! ping -c3 ${NSX_CONTROLLER} &>/dev/null; do
  sleep 2
done

SSH_OPTIONS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

# Create cluster
echo "Note: Creating NSX cluster"
sudo yum install -y -q sshpass
sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_CONTROLLER_IP} join control-cluster ${NSX_CONTROLLER_IP}
sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_SERVICE_IP} set switch manager-cluster ${NSX_CONTROLLER_IP}

# login to controller
echo "Note: Authenticating against controller"
curl -k -c cookie.txt -X POST -d 'username=admin&password=admin' https://${NSX_CONTROLLER}/ws.v1/login

# wait for cluster to be ready
echo "Note: waiting for controller to be ready"
while ! curl -sD - -k -b cookie.txt  https://${NSX_CONTROLLER}/ws.v1/control-cluster  | grep "HTTP/1.1 200"; do
  sleep 5
done

# create the transport zone
echo "Note: Creating Transport Zone"
curl -k -b cookie.txt -X POST -d '{ "display_name": "mct-zone" }' https://${NSX_CONTROLLER}/ws.v1/transport-zone 2> /dev/null 1> transport-zone.json

# retrieve the transport zone uuid (to use further down the line)
transportZoneUuid="$(cat transport-zone.json | sed -e 's/^.*"uuid": "//' -e 's/", .*$//')"

# create service node
echo "Note: Creating Service Node in Zone with UUID = ${transportZoneUuid}"
curl -k -b cookie.txt -X POST -d '{
    "credential": {
        "mgmt_address": "'"${NSX_SERVICE_IP}"'",
        "type": "MgmtAddrCredential"
    },
    "display_name": "mct-service-node",
    "transport_connectors": [
        {
            "ip_address": "'"${NSX_SERVICE_IP}"'",
            "type": "VXLANConnector",
            "transport_zone_uuid": "'"${transportZoneUuid}"'"
        },
        {
            "ip_address": "'"${NSX_SERVICE_IP}"'",
            "type": "STTConnector",
            "transport_zone_uuid": "'"${transportZoneUuid}"'"
        }
    ],
    "zone_forwarding": true
}' https://${NSX_CONTROLLER}/ws.v1/transport-node 2> /dev/null 1> transport-node-service.json

# Setup KVM host
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
            "type": "VXLANConnector"
        },
        {
            "ip_address": "'"${KVM_HOST_IP}"'",
            "transport_zone_uuid": "'"${transportZoneUuid}"'",
            "type": "STTConnector"
        }
    ]
}' https://${NSX_CONTROLLER}/ws.v1/transport-node 2> /dev/null 1> transport-node-${KVM_HOST}.json

