#! /bin/bash

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
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

function destroy_vm {
  vmname=$1

  /data/vm-easy-deploy/remove_vm.sh -f ${vmname}
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

# username hypervisor 1
hvuser1=$(cat ${marvin_config} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][0]['username']
except:
 print ''
")

# password hypervisor 1
hvpass1=$(cat ${marvin_config} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][0]['password']
except:
 print ''
")

# ip adress hypervisor 1
hvip1=$(cat ${marvin_config} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][0]['url']
except:
 print ''
" | cut -d/ -f3)

# username hypervisor 2
hvuser2=$(cat ${marvin_config} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][1]['username']
except:
 print ''
")

# password hypervisor 2
hvpass2=$(cat ${marvin_config} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][1]['password']
except:
 print ''
")

# ip adress hypervisor 2
hvip2=$(cat ${marvin_config} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][1]['url']
except:
 print ''
" | cut -d/ -f3)

cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Collecting Management Server Logs"
collect_files_from_vm ${cs1ip} "root" "password" "~tomcat/vmops.log*" "."
collect_files_from_vm ${cs1ip} "root" "password" "~tomcat/api.log*"   "."

say "Collecting Hypervisor Agent Logs"
mkdir -p kvm1-agent-logs kvm2-agent-logs
collect_files_from_vm ${hvip1} ${hvuser1} ${hvpass2} "/var/log/cloudstack/agent/agent.log*" "kvm1-agent-logs/"
collect_files_from_vm ${hvip2} ${hvuser2} ${hvpass2} "/var/log/cloudstack/agent/agent.log*" "kvm2-agent-logs/"

say "Collecting Marvin Logs"
cp -rf /tmp/MarvinLogs .
rm -rf /tmp/MarvinLogs

destroy_vm cs1
destroy_vm ${hvip1}
destroy_vm ${hvip2}
