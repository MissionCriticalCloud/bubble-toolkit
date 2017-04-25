#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

say "Build cosmic-usage-chart"
make

wait_timeout=600
say "Install Cosmic Usage using cosmic-usage-chart (will wait for ${wait_timeout} seconds to complete)"
helm install cosmic/microservices/cosmic-usage-chart \
--name=cosmic-release \
--namespace=cosmic \
--values=/data/shared/deploy/cosmic/kubernetes/helm/values/cosmic-microservices-chart.yaml \
--replace \
--wait \
--timeout ${wait_timeout}

