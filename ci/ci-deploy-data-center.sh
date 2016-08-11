#!/bin/bash
. `dirname $0`/../helper_scripts/cosmic/helperlib.sh
set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

say "Running script: $0"

function update_management_server_in_marvin_config {
  marvin_config=$1
  csip=$2

  sed -i "s/\"mgtSvrIp\": \"localhost\"/\"mgtSvrIp\": \"${csip}\"/" ${marvin_config}

  say "Management Server in Marvin Config updated to ${csip}"
}

function wait_for_port {
  hostname=$1
  port=$2
  transport=$3

  while ! nmap -Pn -p${port} ${hostname} | grep "${port}/${transport} open" 2>&1 > /dev/null; do sleep 1; done
}

function wait_for_management_server {
  hostname=$1

  say "Waiting for CloudStack Management Server to be running on ${hostname}"
  wait_for_port ${hostname} 8096 tcp
}

function wait_for_systemvm_templates {
  hostname=$1

  say "Waiting for SystemVM templates to be ready on ${hostname}"
  /data/shared/helper_scripts/cloudstack/wait_template_ready.py -t ${hostname}
}

function deploy_data_center {
  marvin_config=$1

  python -m marvin.deployDataCenter -i ${marvin_config}

  say "Data center deployed"
}

# Options
while getopts ':m:' OPTION
do
  case $OPTION in
  m)    marvin_config="$OPTARG"
        ;;
  esac
done

say "Received arguments:"
say "marvin_config = ${marvin_config}"

# Check if a marvin dc file was specified
if [ -z ${marvin_config} ]; then
  say "No Marvin config specified. Quiting."
  usage
  exit 1
else
  say "Using Marvin config '${marvin_config}'."
fi

if [ ! -f "${marvin_config}" ]; then
    say "Supplied Marvin config not found!"
    exit 1
fi

parse_marvin_config ${marvin_config}

wait_for_management_server ${cs1ip}

say "Making local copy of Marvin Config file"
cp ${marvin_config} .

marvin_configCopy=$(basename ${marvin_config})

say "Updating Marvin Config with Management Server IP"
update_management_server_in_marvin_config ${marvin_configCopy} ${cs1ip}

parse_marvin_config ${marvin_configCopy}

say "Deploying Data Center"
deploy_data_center ${marvin_configCopy}

wait_for_systemvm_templates ${cs1ip}
