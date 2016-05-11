#!/bin/bash

# We get this passed from the main script
NEWHOST=$1
echo "Note: Waiting for the VM to boot..."
# Wait until the VM is alive
while ! ping -c1 ${NEWHOST} &>/dev/null; do :; done
echo "Note: Ping result for ${NEWHOST}"
ping -c1 ${NEWHOST}
