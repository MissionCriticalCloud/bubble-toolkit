#! /bin/bash

set -e

function usage {
  printf "Usage: %s: -m marvin_config -h requires_hardware test1 test2 ... testN\n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

function update_management_server_in_marvin_config {
  marvin_config=$1
  csip=$2

  sed -i "s/\"mgtSvrIp\": \"localhost\"/\"mgtSvrIp\": \"${csip}\"/" ${marvin_config}

  say "Management Server in Marvin Config updated to ${csip}"
}

function run_marvin_tests {
  config_file=$1
  require_hardware=$2
  tests="$3"

  nose_tests_report_file=nosetests-required_hardware-${require_hardware}.xml

  cd cosmic-core/test/integration
  nosetests --with-xunit --xunit-file=../../../${nose_tests_report_file} --with-marvin --marvin-config=../../../${config_file} -s -a tags=advanced,required_hardware=${require_hardware} ${tests}
  cd -
}

# Options
while getopts ':m:h:' OPTION
do
  case $OPTION in
  m)    marvin_config="$OPTARG"
        ;;
  h)    require_hardware="$OPTARG"
        ;;
  esac
done

marvin_tests=${@:$OPTIND}

say "Received arguments:"
say "marvin_config = ${marvin_config}"
say "marvin_tests = \"${marvin_tests}\""

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

# Check if a marvin dc file was specified
if [ -z "${marvin_tests}" ]; then
  say "No Marvin Tests Specified. Quiting."
  usage
  exit 2
fi

cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Making local copy of Marvin Config file"
cp ${marvin_config} .

marvin_config_copy=$(basename ${marvin_config})
cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Updating Marvin Config with Management Server IP"
update_management_server_in_marvin_config ${marvin_config_copy} ${cs1ip}

say "Running tests"
run_marvin_tests ${marvin_config_copy} ${require_hardware} "${marvin_tests}"
