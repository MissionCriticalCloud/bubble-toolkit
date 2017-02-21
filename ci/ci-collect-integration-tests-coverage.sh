#! /bin/bash
. `dirname $0`/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s:\n" $(basename $0) >&2
}

say "Running script: $0"


function collect_files_from_vm {
  vmip=$1
  vmuser=$2
  vmpass=$3
  file_pattern=$4
  destination=$5

  # SCP helpers
  set_ssh_base_and_scp_base ${vmpass}


  ${scp_base} ${vmuser}@${vmip}:${file_pattern} ${destination}
}

function stop_tomcat {
  vmip=$1
  vmuser=$2
  vmpass=$3

  set_ssh_base_and_scp_base ${vmpass}


  ${ssh_base} ${vmuser}@${vmip} systemctl stop tomcat
}

function stop_agent {
  vmip=$1
  vmuser=$2
  vmpass=$3

  set_ssh_base_and_scp_base ${vmpass}

  ${ssh_base} ${vmuser}@${vmip} systemctl stop cosmic-agent
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

for i in 1 2 3 4 5 6 7 8 9; do
  if  [ ! -v $( eval "echo \${cs${i}ip}" ) ]; then
    csuser=
    csip=
    cspass=
    eval csuser="\${cs${i}user}"
    eval csip="\${cs${i}ip}"
    eval cspass="\${cs${i}pass}"
    say "Stopping Tomcat"
    stop_tomcat ${csip} ${csuser} ${cspass}

    say "Collecting Integration Tests Coverage Data (Management Server)"
    collect_files_from_vm ${csip} ${csuser} ${cspass} "/tmp/jacoco-it.exec" "target/coverage-reports/jacoco-it-cs${i}.exec"
  fi
done

for i in 1 2 3 4 5 6 7 8 9; do
  if  [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
    hvuser=
    hvip=
    hvpass=
    eval hvuser="\${hvuser${i}}"
    eval hvip="\${hvip${i}}"
    eval hvpass="\${hvpass${i}}"
    say "Stopping Cosmic KVM Agent on host ${hvip}"
    stop_agent ${hvip} ${hvuser} ${hvpass}

    say "Collecting Integration Tests Coverage Data (Agent)"
    collect_files_from_vm ${hvip} ${hvuser} ${hvpass} "/tmp/jacoco-it.exec" "target/coverage-reports/jacoco-it-kvm${i}.exec"
  fi
done


