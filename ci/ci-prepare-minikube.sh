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


until minikube_start ${minikube_destroy}
do
  say "minikube failed to start, retrying."
done

minikube_get_ip

say "Waiting for kubernetes to be available."
until (echo > /dev/tcp/${MINIKUBE_IP}/8443) &> /dev/null; do
    sleep 1 
done

if [ "${minikube_destroy}" == "true" ]; then
  # Create cosmic namespace
  kubectl create namespace cosmic
  kubectl create namespace internal
else
  kubectl delete --all deployments  --namespace=cosmic
  kubectl delete --all services  --namespace=cosmic
fi

# Setup docker registry with certificates
cosmic_docker_registry ${minikube_destroy}

say "Starting deployment: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/rabbitmq.yml

say "Starting service: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/rabbitmq.yml

say "Starting deployment: mariadb"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/mariadb.yml

say "Starting service: mariadb"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/mariadb.yml

