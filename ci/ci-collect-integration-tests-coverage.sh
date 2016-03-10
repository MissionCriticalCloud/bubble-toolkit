#! /bin/bash

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

cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Stopping Tomcat"
stop_tomcat ${cs1ip} "root" "password" 

say "Collecting Integration Tests Coverage Data"
collect_files_from_vm ${cs1ip} "root" "password" "/tmp/jacoco-it.exec" "target/coverage-reports"
