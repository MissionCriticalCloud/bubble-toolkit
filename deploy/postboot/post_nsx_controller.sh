#! /bin/bash

NSX_CONTROLLER=$1
# We get this passed from the main script
NEWHOST=$2

NSX_CONTROLLER_IP=$(getent hosts ${NSX_CONTROLLER} | awk '{ print $1 }')

SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

sudo yum install -y -q sshpass

echo "Joining cluster"
sshpass -p 'admin' ssh ${SSH_OPTIONS} admin@${NEWHOST} join control-cluster ${NSX_CONTROLLER_IP}
