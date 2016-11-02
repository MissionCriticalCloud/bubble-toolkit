#!/usr/bin/env bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

minikube_get_ip

function cosmic_usage_db {
    say "Setup Cosmic usage database"
    say "Starting deployment: mariadb"
    kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/mariadb-deployment.yml

    say "Starting service: mariadb"
    kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/mariadb-service.yml

    say "Waiting for mariadb to be available."
    until (mysql -h ${minikube_ip} -u root -ppassword -P 30061 mysql -e"SHOW databases;" --connect-timeout=5) &> /dev/null 
    do
        sleep 10
    done

    say "Create Cosmic usage database"
    mysql -h ${minikube_ip} -u root -ppassword -P 30061 mysql -e"create database \`usage\`;"
}

cosmic_usage_db

say "Starting deployment: registry"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/registry-deployment.yml

say "Starting service: registry"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/registry-service.yml

say "Starting deployment: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/rabbitmq-deployment.yml

say "Starting service: rabbitmq"
kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/rabbitmq-service.yml
