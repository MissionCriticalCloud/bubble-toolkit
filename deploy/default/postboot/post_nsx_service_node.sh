#!/usr/bin/env bash

NSX_SERVICE_NODE=$1

echo "Note: Waiting for the VM to boot..."
while ! ping -c1 ${NSX_SERVICE_NODE} &>/dev/null; do :; done

echo "Note: Ping result for ${NSX_SERVICE_NODE}"
ping -c1 ${NSX_SERVICE_NODE}

SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "Cleaning service node."
yes | sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_SERVICE_NODE} clear everything