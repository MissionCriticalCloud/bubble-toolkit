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

# Go the the source
COSMIC_BUILD_PATH=/data/git/$HOSTNAME/cosmic
cd $COSMIC_BUILD_PATH
git checkout master

# Get the PR
git fetch origin pull/${prId}/head:pr/${prId}
git checkout pr/${prId}
