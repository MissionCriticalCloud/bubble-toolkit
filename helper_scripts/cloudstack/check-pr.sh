#!/bin/bash

# This script checks out a PR branch and then starts a management server with that code. 
# Next, you can run Marvin to setup whatever you need to verify the PR.

function usage {
  printf "Usage: %s: -m marvinCfg -p <pr id> [ -b <branch: default to master> -s <skip compile> -t <run tests> -T <mvn -T flag> ]\n" $(basename $0) >&2
}

# Options
skip=
run_tests=
compile_threads=
while getopts 'm:p:T:b:st' OPTION
do
  case $OPTION in
  m)    marvinCfg="$OPTARG"
        ;;
  p)    prId="$OPTARG"
        ;;
  s)    skip="-s"
        ;;
  t)    run_tests="-t"
        ;;
  T)    compile_threads="-T $OPTARG"
        ;;
  b)    branch_name="$OPTARG"
        ;;
  esac
done

echo "Received arguments:"
echo "skip = ${skip}"
echo "run_tests = ${run_tests}"
echo "marvinCfg = ${marvinCfg}"
echo "prId = ${prId}"
echo "compile_threads = ${compile_threads}"
echo "branch_name = ${branch_name}"

# Check if a marvin dc file was specified
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  usage
  exit 1
else
  echo "Using Marvin config '${marvinCfg}'."
fi

if [ ! -f "${marvinCfg}" ]; then
    echo "Supplied Marvin config not found!"
    exit 1
fi

# Default to master branch
if [ -z "${branch_name}" ]; then
    branch_name="master"
    echo "branch_name = ${branch_name}"
fi

echo "Started!"
date

# Check if a pull request id was specified
if [ -z ${prId} ]; then
  echo "No PR number specified. Quiting."
  usage
  exit 1
fi

# Check if a marvin dc file was specified
if [ -z ${marvinCfg} ]; then
  echo "No Marvin config specified. Quiting."
  usage
  exit 1
fi

# Perpare, checkout and stuff
/data/shared/helper_scripts/cloudstack/prepare_cloudstack_compile.sh

# Go the the source
cd /data/git/${HOSTNAME}/cloudstack
git reset --hard
git checkout ${branch_name}
git branch --set-upstream-to=origin/${branch_name} ${branch_name}
git pull --rebase

# Get the PR
git branch -D pr/${prId}
git fetch origin pull/${prId}/head:pr/${prId}
if [ $? -gt 0  ]; then
  echo "ERROR: Fetching failed!"
  exit 1
fi
git checkout pr/${prId}
if [ $? -gt 0  ]; then
  echo "ERROR: Checkout failed!"
  exit 1
fi

# Rebase with current ${branch_name} before tests
git rebase ${branch_name}
if [ $? -gt 0  ]; then
  echo "ERROR: Rebase with ${branch_name} failed, please ask author to rebase and force-push commits. Then try again!"
  exit 1
fi

# Build, run and test it
/data/shared/helper_scripts/cloudstack/build_run_deploy_test.sh -m ${marvinCfg} ${run_tests} ${skip} ${compile_threads}
