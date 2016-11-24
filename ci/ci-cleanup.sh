#! /bin/bash
. `dirname $0`/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

say "Running script: $0"

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

function destroy_vm {
  vmname=$1

  /data/shared/deploy/kvm_local_deploy.py -x ${vmname}
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
  if [ ! -v $( eval "echo \${cs${i}ip}" ) ]; then
    csuser=
    csip=
    cspass=
    eval csuser="\${cs${i}user}"
    eval csip="\${cs${i}ip}"
    eval cspass="\${cs${i}ip}"

    say "Collecting Management Server Logs and Code Coverage Report from ${csip}"
    mkdir -p cs${i}-management-logs
    collect_files_from_vm ${csip} ${csuser} ${cspass} "/var/log/cosmic/management/*.log*" "cs${i}-management-logs/"
    say "Destroying VM ${csip}"
    destroy_vm ${csip}
  fi

  if [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
      hvuser=
      hvip=
      hvpass=
      eval hvuser="\${hvuser${i}}"
      eval hvip="\${hvip${i}}"
      eval hvpass="\${hvpass${i}}"

    say "Collecting Hypervisor Agent Logs"
    mkdir -p kvm${i}-agent-logs
    collect_files_from_vm ${hvip} ${hvuser} ${hvpass} "/var/log/cosmic/agent/agent.log*" "kvm${i}-agent-logs/"

    say "Destroying VM ${hvip}"
    destroy_vm ${hvip}
  fi
done
say "Cleaning primary and secondary NFS storage"
sudo rm -rf /data/storage/secondary/*/*
sudo rm -rf /data/storage/primary/*/*
