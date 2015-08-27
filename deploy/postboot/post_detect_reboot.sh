#!/bin/bash

# We get this passed from the main script
NEWHOST=$1
echo "Note: Waiting for the VM to boot..."
# Wait until the VM is alive
while ! ping -c1 ${NEWHOST} &>/dev/null; do :; done
echo "Note: Installing and configuring ${NEWHOST}"
echo "Note: This will take some time. You may send this to the background."
while ping -c1 ${NEWHOST} &>/dev/null; do :; done
echo "Note: Rebooting ${NEWHOST}"
while ! ping -c1 ${NEWHOST} &>/dev/null; do :; done
sleep 15
echo "Note: ${NEWHOST} is ready for duty!"
