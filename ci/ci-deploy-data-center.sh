#!/bin/bash
. `dirname $0`/../helper_scripts/cosmic/helperlib.sh
set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
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

  say "Waiting for Cosmic Management Server to be running on ${hostname}"
  wait_for_port ${hostname} 8096 tcp
}

function wait_for_systemvm_templates {
  hostname=$1

  say "Waiting for SystemVM templates to be ready on ${hostname}"
  /data/shared/helper_scripts/cosmic/wait_template_ready.py -t ${hostname}
}

function deploy_data_center {
  marvin_config=$1

  python -m marvin.deployDataCenter -i ${marvin_config}

  say "Data center deployed"
}

function add_nsx_connectivy_to_offerings {
  csip=$1

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.ntwk_offering_service_map (network_offering_id, service, provider, created) (SELECT DISTINCT X.network_offering_id, 'Connectivity', 'NiciraNvp', X.created FROM cloud.ntwk_offering_service_map X);"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.vpc_offering_service_map (vpc_offering_id, service, provider, created) (SELECT DISTINCT X.vpc_offering_id, 'Connectivity', 'NiciraNvp', X.created FROM cloud.vpc_offering_service_map X);"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.ntwk_offering_service_map (network_offering_id, service, provider, created) (SELECT DISTINCT X.id, 'Connectivity', 'NiciraNvp', X.created FROM cloud.network_offerings X WHERE name = 'System-Private-Gateway-Network-Offering');"
}

function add_nsx_controller_to_cosmic {
  bash -x /tmp/nsx_cosmic.sh
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

if  [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then
  add_nsx_connectivy_to_offerings ${cs1ip}
  add_nsx_controller_to_cosmic
fi

wait_for_systemvm_templates ${cs1ip}
