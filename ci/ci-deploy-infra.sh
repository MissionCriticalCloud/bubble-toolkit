#! /bin/bash

set -e

sudo yum install -y -q sshpass

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

function wait_for_port {
  hostname=$1
  port=$2
  transport=$3

  while ! nmap -Pn -p${port} ${hostname} | grep "${port}/${transport} open" 2>&1 > /dev/null; do sleep 1; done
}

function wait_for_mysql_server {
  hostname=$1

  say "Waiting for MySQL Server to be running on ${hostname}"
  wait_for_port ${hostname} 3306 tcp
}

function install_kvm_packages {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # scp packages to hypervisor, remove existing, then install new ones
  ${ssh_base} ${hvuser}@${hvip} rm -f cosmic-\*
  ${scp_base} cosmic-agent*.rpm cosmic-common*.rpm ${hvuser}@${hvip}:./
  ${ssh_base} ${hvuser}@${hvip} yum -y -q remove cosmic-common
  ${ssh_base} ${hvuser}@${hvip} rm -f /etc/cosmic/agent/agent.properties
  ${ssh_base} ${hvuser}@${hvip} yum -y localinstall cosmic-agent\*.rpm cosmic-common\*.rpm
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload
  ${ssh_base} ${hvuser}@${hvip} systemctl stop cosmic-agent
  ${ssh_base} ${hvuser}@${hvip} sed -i 's/INFO/DEBUG/g' /etc/cosmic/agent/log4j-cloud.xml
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.cpu.mode=host-model" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "network.bridge.type=openvswitch" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "public.network.device=pub0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "private.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'

  say "KVM packages installed in ${hvip}"
}

function deploy_cosmic_db {
  csip=$1
  csuser=$2
  cspass=$3

  wait_for_mysql_server ${csip}

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  ${ssh_base} ${csuser}@${csip} "mysql -u root -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;\""
  mysql -h ${csip} -u root < setup/db/create-database.sql
  mysql -h ${csip} -u root < setup/db/create-database-premium.sql
  mysql -h ${csip} -u root < setup/db/create-schema.sql
  mysql -h ${csip} -u root < setup/db/create-schema-premium.sql
  mysql -h ${csip} -u cloud -pcloud < setup/db/templates.sql
  mysql -h ${csip} -u cloud -pcloud < developer/developer-prefill.sql

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '${csip}') ON DUPLICATE KEY UPDATE value = '${csip}';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'sdn.ovs.controller.default.label', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"

  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE cloud.vm_template SET url='http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2' where id=3;"
  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-kvm.qcow2.bz2', guest_os_id=140, name='tiny linux kvm', display_text='tiny linux kvm', hvm=1 where id=4;"

  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE service_offering SET ha_enabled = 1;"
  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE vm_instance SET ha_enabled = 1;"

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.private.network.device', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.public.network.device', 'pub0') ON DUPLICATE KEY UPDATE value = 'pub0';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.guest.network.device', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"

  say "Cosmic DB deployed at ${csip}"
}

function install_marvin {
  marvin_dist=$1

  sudo pip install --upgrade ${marvin_dist}
  sudo pip install nose --upgrade --force

  say "Marvin installed"
}

function install_systemvm_templates {
  csip=$1
  csuser=$2
  cspass=$3
  secondarystorage=$4
  systemtemplate=$5
  hypervisor=$6
  imagetype=$7

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  ${scp_base} -r ./scripts ${csuser}@${csip}:./
  ${ssh_base} ${csuser}@${csip} ./scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondarystorage} -f ${systemtemplate} -h ${hypervisor} -o localhost -r root -e ${imagetype} -F

  say "SystemVM templates installed"
}

function deploy_cosmic_war {
  csip=$1
  csuser=$2
  cspass=$3
  dbscripts_dir="$4"
  war_file="$5"

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  ${ssh_base} ${csuser}@${csip} mkdir -p ~tomcat/db
  ${scp_base} ${dbscripts_dir} ${csuser}@${csip}:~tomcat/db/
  ${scp_base} ${war_file} ${csuser}@${csip}:~tomcat/webapps/client.war
  ${ssh_base} ${csuser}@${csip} service tomcat start
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


zone=$(cat ${marvin_config} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['name']
")

# Hypervisor type
hypervisor=$(cat ${marvin_config} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hypervisor'].lower()
")

# Primary storage location
primarystorage=$(cat ${marvin_config} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['primaryStorages'][0]['url']" | cut -d: -f3
)
mkdir -p ${primarystorage}

secondarystorage=$(cat ${marvin_config} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['secondaryStorages'][0]['url']" | cut -d: -f3
)
mkdir -p ${secondarystorage}

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

say "Cleaning storage"
sudo rm -rf /data/storage/secondary/*/*
sudo rm -rf /data/storage/primary/*/*

say "Creating Management Server: cs1"
/data/shared/deploy/kvm_local_deploy.py -r cloudstack-mgt-dev -d 1 --force

cs1ip=$(getent hosts cs1 | awk '{ print $1 }')

say "Deploying Cosmic DB"
deploy_cosmic_db ${cs1ip} "root" "password"

say "Installing Marvin"
install_marvin "https://beta-nexus.mcc.schubergphilis.com/service/local/artifact/maven/redirect?r=snapshots&g=cloud.cosmic&a=cloud-marvin&v=LATEST&p=tar.gz"

say "Installing SystemVM templates"
systemtemplate="/data/templates/cosmic-systemvm.qcow2"
imagetype="qcow2"
install_systemvm_templates ${cs1ip} "root" "password" ${secondarystorage} ${systemtemplate} ${hypervisor} ${imagetype}

say "Deploying Cosmic WAR"
deploy_cosmic_war ${cs1ip} "root" "password" 'client/target/utilities/scripts/db/db/*' 'client/target/cloud-client-ui-*.war'

say "Creating hosts"
/data/shared/deploy/kvm_local_deploy.py -m ${marvin_config} --force

say "Installing KVM packages on hosts"
install_kvm_packages ${hvip1} ${hvuser1} ${hvpass1}
install_kvm_packages ${hvip2} ${hvuser2} ${hvpass2}
