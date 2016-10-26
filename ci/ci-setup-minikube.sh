#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

say "Starting deployment: mariadb"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/mariadb-deployment.yml

say "Starting service: mariadb"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/mariadb-service.yml

say "Starting deployment: registry"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/registry-deployment.yml

say "Starting service: registry"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/registry-service.yml
