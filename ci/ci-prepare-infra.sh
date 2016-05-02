#! /bin/bash

set -e

sudo yum install -y -q sshpass

function usage {
  echo "This script prepares the required infrastructure for integration tests, based on a marvin configuration file"
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

# Options
while getopts ':m:' OPTION
do
  case $OPTION in
  m)    marvin_config="$OPTARG"
        ;;
  esac
done

say "Received arguments:"
say "marvin_config = ${marvin_config}"

# Check if a marvin dc file was specified
if [ -z ${marvin_config} ]; then
  say "No Marvin config specified. Quiting."
  usage
  exit 1
else
  say "Using Marvin config '${marvin_config}'."
fi

if [ ! -f "${marvin_config}" ]; then
    say "Supplied Marvin config not found!"
    exit 1
fi

# Primary storage location
primarystorage=$(cat ${marvin_config} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['primaryStorages'][0]['url']" | cut -d: -f3
)
mkdir -p ${primarystorage}

say "Creating Management Server: cs1"
/data/shared/deploy/kvm_local_deploy.py -r cloudstack-mgt-dev -d 1 --force

cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Creating hosts"
/data/shared/deploy/kvm_local_deploy.py -m ${marvin_config} --force
