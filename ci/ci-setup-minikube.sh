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

    say "Waiting for mariadb to be available."
    until (mysql -h ${MINIKUBE_IP} -u root -ppassword -P 30061 mysql -e"SHOW databases;" --connect-timeout=5) &> /dev/null 
    do
        sleep 10
    done

    say "Create Cosmic usage database"
    mysql -h ${MINIKUBE_IP} -u root -ppassword -P 30061 mysql -e"create database \`usage\`;"
}

# Setup usage db/container
cosmic_usage_db

say "Starting deployment: cosmic-config-server"
cat /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-config-server.yml | sed "s/image: .*cosmic-config-server/image: ${MINIKUBE_HOST}:30081\/cosmic-config-server/g" | kubectl create -f -

say "Starting deployment: cosmic-usage-db-api"
cat /data/shared/deploy/cosmic/kubernetes/deployments/cosmic-usage-db-api.yml | sed "s/image: .*cosmic-usage-db-api/image: ${MINIKUBE_HOST}:30081\/cosmic-usage-db-api/g" | kubectl create -f -

