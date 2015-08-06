#!/bin/bash

# This script checks out a PR branch and then starts a management server with that code. 
# Next, you can run Marvin to setup whatever you need to verify the PR.

# Stop executing when we encounter errors
set -e

# Check if a pull request id was specified
prId=$1
if [ -z ${prId} ]; then
  echo "No PR number specified. Quiting."
  exit 1
fi

# Perpare, checkout and stuff
/data/shared/helper_scripts/cloudstack/prepare_cloudstack_compile.sh

# Go the the source
cd /data/git/${HOSTNAME}/cloudstack

# Get the PR
git fetch origin pull/${prId}/head:pr/${prId}
git checkout pr/${prId}

# Build and run it
/data/shared/helper_scripts/cloudstack/build_run.sh
