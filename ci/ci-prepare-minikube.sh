#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

say "Running script: $0"

if [ -z $1 ]; then
  minikube_destroy="true"
else
  minikube_destroy=$1
fi

# Create local docker network for microservices unit tests
# Make sure docker is not redirected to e.g. minikube
unset DOCKER_HOST
unset DOCKER_TLS_VERIFY
if ! docker network ls | grep cosmic-network &>/dev/null; then
  docker network create cosmic-network
fi

until minikube_start ${minikube_destroy}
do
  say "minikube failed to start, retrying."
done

say "Waiting for kubernetes to be available."
until (echo > /dev/tcp/minikube/8443) &> /dev/null;     do echo -n .; sleep 1; done; echo ""

if [ "${minikube_destroy}" == "true" ]; then
  # Create namespaces
  kubectl create namespace internal
  kubectl create namespace cosmic
fi

# Setup docker registry with certificates
cosmic_docker_registry ${minikube_destroy}

say "Initialize Helm."
until [[ $(kubectl get namespace kube-system) =~ 'Active' ]] &> /dev/null; do echo -n .; sleep 1; done; echo ""
helm init --upgrade
until [[ $(kubectl get deployment --namespace=kube-system tiller-deploy -o custom-columns=:.status.availableReplicas) =~ 1 ]] &> /dev/null; do echo -n .; sleep 1; done; echo ""

# Remove previous Helm cosmic-release deployment, if present
if [[ $(helm ls) =~ cosmic-release ]]; then helm delete cosmic-release; fi

say "Done running script: $0"
