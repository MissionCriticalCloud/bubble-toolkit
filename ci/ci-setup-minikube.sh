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
--set namespace=cosmic \
--set registry="minikube.cloud.lan:30081/" \
--set cosmic_usage_ui.usage_api_base_url="http://minikube.cloud.lan:31001/" \
--set dev_mode=true \
--replace \
--wait
