#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

say "Running script: $0"

until minikube_start "true"
do
  say "minikube failed to start, retrying."
done

minikube_get_ip

say "Waiting for kubernetes to be available."
until (echo > /dev/tcp/${minikube_ip}/8443) &> /dev/null; do
    sleep 1 
done
