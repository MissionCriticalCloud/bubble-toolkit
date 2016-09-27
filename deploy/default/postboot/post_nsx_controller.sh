#!/usr/bin/env bash

NSX_CONTROLLER_NODE=$1

echo "Note: Waiting for the VM to boot..."
while ! ping -c1 ${NSX_CONTROLLER_NODE} &>/dev/null; do :; done

echo "Note: Ping result for ${NSX_CONTROLLER_NODE}"
ping -c1 ${NSX_CONTROLLER_NODE}

SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "Cleaning controller node."
echo 'yes' | sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_CONTROLLER_NODE} clear everything
echo 'y' | sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NSX_CONTROLLER_NODE} restart system
