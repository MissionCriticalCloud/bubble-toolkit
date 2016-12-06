#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

minikube_get_ip

say "Starting deployment: cosmic-config-server"
cat /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-config-server.yml | sed "s/image: .*cosmic-config-server/image: ${MINIKUBE_HOST}:30081\/cosmic-config-server/g" | kubectl create -f -
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/cosmic-config-server.yml


