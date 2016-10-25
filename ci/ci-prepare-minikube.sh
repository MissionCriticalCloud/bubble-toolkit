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
while ! nc -w 2 -v ${minikube_ip} 8443 </dev/null; do
  sleep 1 # wait for 1/10 of the second before check again
done
