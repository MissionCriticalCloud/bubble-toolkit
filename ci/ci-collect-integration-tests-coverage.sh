#! /bin/bash
. `dirname $0`/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s:\n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

function collect_files_from_vm {
  vmip=$1
  vmuser=$2
  vmpass=$3
  file_pattern=$4
  destination=$5

  # SCP helpers
  scp_base="sshpass -p ${vmpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  ${scp_base} ${vmuser}@${vmip}:${file_pattern} ${destination}
}

function stop_tomcat {
  vmip=$1
  vmuser=$2
  vmpass=$3

  ssh_base="sshpass -p ${vmpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  ${ssh_base} ${vmuser}@${vmip} systemctl stop tomcat
}

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

say "Stopping Tomcat"
stop_tomcat ${cs1ip} ${cs1user} ${cs1pass}

say "Collecting Integration Tests Coverage Data"
collect_files_from_vm ${cs1ip} ${cs1user} ${cs1pass} "/tmp/jacoco-it.exec" "target/coverage-reports"
