#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

minikube_get_ip

say "Deploying containers using Helm"
helm install . --name=cosmic-release --set namespace=cosmic,registry=${MINIKUBE_HOST}:30081/,dev_mode=true --replace --wait
