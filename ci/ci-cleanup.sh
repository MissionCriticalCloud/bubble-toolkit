#!/usr/bin/env bash

# We need to be root to do the cleanup of all NFS files
sudo $(dirname $0)/ci-cleanup.py $*