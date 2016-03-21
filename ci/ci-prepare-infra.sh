#! /bin/bash

set -e

sudo yum install -y -q sshpass

function usage {
  echo "This script prepares the required infrastructure for integration tests, based on a marvin configuration file"
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

function install_mysql_connector {
  csip=$1
  csuser=$2
  cspass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  ${ssh_base} ${csuser}@${csip} yum install -y -q mysql-connector-java

  say "MySQL Connector Java installed"
}

function configure_tomcat_to_load_mysql_connector {
  csip=$1
  csuser=$2
  cspass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  ${ssh_base} ${csuser}@${csip} "echo \"CLASSPATH=\\\"/usr/share/java/mysql-connector-java.jar\\\"\" >> /etc/sysconfig/tomcat"
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

# Primary storage location
primarystorage=$(cat ${marvin_config} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['primaryStorages'][0]['url']" | cut -d: -f3
)
mkdir -p ${primarystorage}

say "Creating Management Server: cs1"
/data/shared/deploy/kvm_local_deploy.py -r cloudstack-mgt-dev -d 1 --force

cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Installing MySQL Connector Java"
install_mysql_connector ${cs1ip} "root" "password"

say "Configure Tomcat to load MySQL Connector"
configure_tomcat_to_load_mysql_connector ${cs1ip} "root" "password"

say "Creating hosts"
/data/shared/deploy/kvm_local_deploy.py -m ${marvin_config} --force
