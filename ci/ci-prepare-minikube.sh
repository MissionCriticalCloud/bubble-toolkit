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

say "Starting deployment: elasticsearch"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/elasticsearch.yml

say "Starting service: elasticsearch"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/elasticsearch.yml

say "Adding logstash.conf file"
kubectl create secret generic logstash-files --from-file=/data/shared/ci/setup_files/logstash.conf --from-file=/data/shared/ci/setup_files/cosmic-metrics-template.json --namespace=cosmic

say "Starting deployment: logstash"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/logstash.yml

say "Starting deployment: cosmic-vault"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-vault.yml

say "Starting service: cosmic-vault"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/cosmic-vault.yml

say "Waiting for cosmic-vault to be available."
until curl -m 5 -sD - http://${MINIKUBE_IP}:30131/v1/sys/health | grep "HTTP/1.1 200" &>/dev/null
do echo -n .; sleep 1; done; echo ""

curl \
    -H "X-Vault-Token: cosmic-vault-token" \
    -H "Content-Type: application/json" \
    -X POST \
    -d @/data/shared/ci/setup_files/cosmic-metrics-collector-config.json \
    http://${MINIKUBE_IP}:30131/v1/secret/cosmic-metrics-collector

curl \
    -H "X-Vault-Token: cosmic-vault-token" \
    -H "Content-Type: application/json" \
    -X POST \
    -d @/data/shared/ci/setup_files/cosmic-usage-api-config.json \
    http://${MINIKUBE_IP}:30131/v1/secret/cosmic-usage-api
