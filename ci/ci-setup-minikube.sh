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
cat /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-config-server.yml | sed "s/image: .*cosmic-config-server/image: ${MINIKUBE_HOST}:30081\/missioncriticalcloud\/cosmic-config-server/g" | kubectl create -f -
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/cosmic-config-server.yml

say "Starting deployment: cosmic-metrics-collector"
cat /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-metrics-collector.yml | sed "s/image: .*cosmic-metrics-collector/image: ${MINIKUBE_HOST}:30081\/missioncriticalcloud\/cosmic-metrics-collector/g" | kubectl create -f -

say "Starting deployment: cosmic-usage-api"
cat /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-usage-api.yml | sed "s/image: .*cosmic-usage-api/image: ${MINIKUBE_HOST}:30081\/missioncriticalcloud\/cosmic-usage-api/g" | kubectl create -f -
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/cosmic-usage-api.yml
