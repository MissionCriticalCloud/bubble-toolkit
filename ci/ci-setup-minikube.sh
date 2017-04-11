#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

say "Deploying containers using Helm"

helm install . \
--name=cosmic-release \
--values=/data/shared/deploy/cosmic/kubernetes/helm/values/cosmic-microservices-chart.yaml \
--replace \
--wait
