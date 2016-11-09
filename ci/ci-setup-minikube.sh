#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

minikube_get_ip

function cosmic_docker_registry {
    say "Generating certificates for registry"
    mkdir -p /tmp/registry/certs
    rm -f /tmp/registry/certs/*
    # Generate self-signed certificate
    openssl req -x509 -sha256 -nodes -newkey rsa:4096 -keyout /tmp/registry/certs/domain.key -out /tmp/registry/certs/domain.crt -days 365 -subj "/C=NL/ST=NH/L=AMS/O=SBP/OU=cosmic/CN=${MINIKUBE_HOST}" &> /dev/null
    # Add certificate to local trust store
    sudo cp /tmp/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
    sudo update-ca-trust
    # Add certificate to the docker deamon (to trust)
    minikube ssh "sudo mkdir -p /etc/docker/certs.d/${MINIKUBE_HOST}:30081"
    cat /tmp/registry/certs/domain.crt | minikube ssh "sudo cat > ca.crt"
    minikube ssh "sudo mv ca.crt /etc/docker/certs.d/${MINIKUBE_HOST}:30081/ca.crt"
    minikube ssh "sudo /etc/init.d/docker restart"

    say "Uploading certificates as secrets"
    kubectl create secret generic registry-certs --from-file=/tmp/registry/certs/domain.crt --from-file=/tmp/registry/certs/domain.key --namespace=cosmic

    say "Starting deployment: registry"
    kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/registry-deployment.yml

    say "Starting service: registry"
    kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/registry-service.yml
}

function cosmic_usage_db {
    say "Setup Cosmic usage database"
    say "Starting deployment: mariadb"
    kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/mariadb-deployment.yml

    say "Starting service: mariadb"
    kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/mariadb-service.yml

    say "Waiting for mariadb to be available."
    until (mysql -h ${MINIKUBE_IP} -u root -ppassword -P 30061 mysql -e"SHOW databases;" --connect-timeout=5) &> /dev/null 
    do
        sleep 10
    done

    say "Create Cosmic usage database"
    mysql -h ${MINIKUBE_IP} -u root -ppassword -P 30061 mysql -e"create database \`usage\`;"
}

# Create cosmic namespace
kubectl create namespace cosmic

# Setup usage db/container
cosmic_usage_db

# Setup docker registry with certificates
cosmic_docker_registry

say "Starting deployment: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/rabbitmq-deployment.yml

say "Starting service: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/rabbitmq-service.yml
