#!/bin/bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config \n" $(basename $0) >&2
}

function say {
  echo "==> $@"
}

say "Running script: $0"

sudo yum install -y -q sshpass

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

  # Cleanup
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload
  ${ssh_base} ${hvuser}@${hvip} systemctl stop cosmic-agent 2>&1 >/dev/null || true
  ${ssh_base} ${hvuser}@${hvip} systemctl disable cosmic-agent 2>&1 >/dev/null || true
  ${ssh_base} ${hvuser}@${hvip} rm -rf /opt/cosmic/
  ${ssh_base} ${hvuser}@${hvip} rm -rf /etc/cosmic/
  ${ssh_base} ${hvuser}@${hvip} rm -rf /var/log/cosmic/
  ${ssh_base} ${hvuser}@${hvip} rm -f /usr/lib/systemd/system/cosmic-agent.service
  ${ssh_base} ${hvuser}@${hvip} rm -f /usr/bin/cosmic-setup-agent
  ${ssh_base} ${hvuser}@${hvip} rm -f /usr/bin/cosmic-ssh
  ${ssh_base} ${hvuser}@${hvip} rm -rf /usr/lib64/python2.7/site-packages/cloudutils
  ${ssh_base} ${hvuser}@${hvip} rm -f /usr/lib64/python2.7/site-packages/cloud_utils.py

  # Copy Agent files to hypervisor
  ${ssh_base} ${hvuser}@${hvip} mkdir -p /opt/cosmic/agent/vms/
  ${ssh_base} ${hvuser}@${hvip} mkdir -p /etc/cosmic/agent/
  ${scp_base} cosmic-agent/target/cloud-agent-*.jar ${hvuser}@${hvip}:/opt/cosmic/agent/
  ${scp_base} cosmic-agent/conf/agent.properties ${hvuser}@${hvip}:/etc/cosmic/agent/
  ${scp_base} -r cosmic-core/scripts/src/main/resources/scripts ${hvuser}@${hvip}:/opt/cosmic/agent/
  ${scp_base} cosmic-core/systemvm/dist/systemvm.iso ${hvuser}@${hvip}:/opt/cosmic/agent/vms/
  ${scp_base} cosmic-agent/bindir/cosmic-setup-agent ${hvuser}@${hvip}:/usr/bin/
  ${scp_base} cosmic-agent/bindir/cosmic-ssh ${hvuser}@${hvip}:/usr/bin/

  if [ -d cosmic-core/scripts/src/main/resources/python ]; then # Prepare for moving/converting to artifact (structure)
    ${scp_base} cosmic-core/scripts/src/main/resources/python/lib/cloud_utils.py ${hvuser}@${hvip}:/usr/lib64/python2.7/site-packages/
    ${scp_base} -r cosmic-core/scripts/src/main/resources/python/lib/cloudutils ${hvuser}@${hvip}:/usr/lib64/python2.7/site-packages/
  else # Following can be removed if python folder is moved to artifact
    ${scp_base} cosmic-core/python/lib/cloud_utils.py ${hvuser}@${hvip}:/usr/lib64/python2.7/site-packages/
    ${scp_base} -r cosmic-core/python/lib/cloudutils ${hvuser}@${hvip}:/usr/lib64/python2.7/site-packages/
  fi

  ${scp_base} cosmic-agent/conf/cosmic-agent.service ${hvuser}@${hvip}:/usr/lib/systemd/system/
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload

  # Set permissions on scripts
  ${ssh_base} ${hvuser}@${hvip} chmod -R 0755 /opt/cosmic/agent/scripts/
  ${ssh_base} ${hvuser}@${hvip} chmod 0755 /usr/bin/cosmic-setup-agent
  ${ssh_base} ${hvuser}@${hvip} chmod 0755 /usr/bin/cosmic-ssh

  # Configure properties
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.cpu.mode=host-model" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "network.bridge.type=openvswitch" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "public.network.device=pub0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "private.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'

  say "Cosmic KVM Agent installed in ${hvip}"
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
  mysql -h ${csip} -u root < cosmic-core/db-scripts/src/main/resources/create-database.sql
  mysql -h ${csip} -u root < cosmic-core/db-scripts/src/main/resources/create-database-premium.sql
  mysql -h ${csip} -u root < cosmic-core/db-scripts/src/main/resources/create-schema.sql
  mysql -h ${csip} -u root < cosmic-core/db-scripts/src/main/resources/create-schema-premium.sql
  mysql -h ${csip} -u cloud -pcloud < cosmic-core/db-scripts/src/main/resources/templates.sql
  mysql -h ${csip} -u cloud -pcloud < cosmic-core/engine/schema/src/test/resources/developer-prefill.sql

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'host', '${csip}') ON DUPLICATE KEY UPDATE value = '${csip}';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'sdn.ovs.controller.default.label', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"

  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE cloud.vm_template SET url='http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2' where id=3;"
  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE cloud.vm_template SET url='http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-kvm.qcow2.bz2', guest_os_id=140, name='tiny linux kvm', display_text='tiny linux kvm', hvm=1 where id=4;"

  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE service_offering SET ha_enabled = 1;"
  mysql -h ${csip} -u cloud -pcloud cloud -e "UPDATE vm_instance SET ha_enabled = 1;"

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'network.gc.interval', '10') ON DUPLICATE KEY UPDATE value = '10';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'network.gc.wait', '10') ON DUPLICATE KEY UPDATE value = '10';"

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'vpc.max.networks', '4') ON DUPLICATE KEY UPDATE value = '4';"

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.private.network.device', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.public.network.device', 'pub0') ON DUPLICATE KEY UPDATE value = 'pub0';"
  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'kvm.guest.network.device', 'cloudbr0') ON DUPLICATE KEY UPDATE value = 'cloudbr0';"

  mysql -h ${csip} -u cloud -pcloud cloud -e "INSERT INTO cloud.configuration (instance, name, value) VALUE('DEFAULT', 'vm.destroy.forcestop', 'true') ON DUPLICATE KEY UPDATE value = '4';"

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


  if [ -d ./cosmic-core/scripts/src/main/resources/scripts ]; then
    ${scp_base} -r ./cosmic-core/scripts/src/main/resources/scripts ${csuser}@${csip}:./
  else
    ${scp_base} -r ./cosmic-core/scripts ${csuser}@${csip}:./
  fi

  ${ssh_base} ${csuser}@${csip} ./scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondarystorage} -f ${systemtemplate} -h ${hypervisor} -o localhost -r root -e ${imagetype} -F

  say "SystemVM templates installed"
}

function configure_tomcat_to_load_jacoco_agent {
  csip=$1
  csuser=$2
  cspass=$3

  # SSH/SCP helpers
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  ${scp_base} target/jacoco-agent.jar ${csuser}@${csip}:/tmp
  ${ssh_base} ${csuser}@${csip} "echo \"JAVA_OPTS=\\\"-javaagent:/tmp/jacoco-agent.jar=destfile=/tmp/jacoco-it.exec\\\"\" >> /etc/sysconfig/tomcat"

  say "Tomcat configured"
}

function configure_agent_to_load_jacococ_agent {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # Enable Java Code Coverage
  ${scp_base} target/jacoco-agent.jar ${hvuser}@${hvip}:/tmp
  ${ssh_base} ${hvuser}@${hvip} "sed -i -e 's/\/bin\/java -Xms/\/bin\/java -javaagent:\/tmp\/jacoco-agent.jar=destfile=\/tmp\/jacoco-it.exec -Xms/' /usr/lib/systemd/system/cosmic-agent.service"
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload

  say "Agent configured"
}

function deploy_cosmic_war {
  csip=$1
  csuser=$2
  cspass=$3
  war_file="$4"

  # SSH/SCP helpers
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${cspass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # Extra configuration for Tomcat's webapp (namely adding /etc/cosmic/management to its classpath)
  ${scp_base} ${scripts_dir}/setup_files/client.xml ${csuser}@${csip}:~tomcat/conf/Catalina/localhost/

  # Extra configuration for Cosmic application
  ${ssh_base} ${csuser}@${csip} mkdir -p /etc/cosmic/management
  ${scp_base} ${scripts_dir}/setup_files/db.properties ${csuser}@${csip}:/etc/cosmic/management
  ${ssh_base} ${csuser}@${csip} "sed -i \"s/cluster.node.IP=/cluster.node.IP=${csip}/\" /etc/cosmic/management/db.properties"

  ${ssh_base} ${csuser}@${csip} mkdir -p /var/log/cosmic/management
  ${ssh_base} ${csuser}@${csip} chown -R tomcat /var/log/cosmic
  ${scp_base} ${war_file} ${csuser}@${csip}:~tomcat/webapps/client.war
  ${ssh_base} ${csuser}@${csip} service tomcat start

  say "WAR deployed"
}

function create_nsx_cluster {
  ssh_base="sshpass -p ${cspass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  nsx_user='admin'
  nsx_pass='admin'

  nsx_cookie=/tmp/nsx_cookie_${$}.txt

  nsx_zone_name='mct-zone'

  nsx_master_controller_node_ip=$( eval "echo \${nsx_controller_node_ip1}" )

  for i in 1 2 3 4 5 6 7 8 9; do
    if  [ ! -v $( eval "echo \${nsx_controller_node_ip${i}}" ) ]; then
    nsx_controller_node_ip=
    eval nsx_controller_node_ip="\${nsx_controller_node_ip${i}}"

    say "Joining ${nsx_controller_node_ip} to cluster."
    configure_nsx_controller_node ${nsx_master_controller_node_ip} ${nsx_controller_node_ip} ${nsx_user} ${nsx_pass}
    fi
  done

  authenticate_nsx ${nsx_master_controller_node_ip} ${nsx_cookie} ${nsx_user} ${nsx_pass}

  check_nsx_cluster_health ${nsx_master_controller_node_ip} ${nsx_cookie}

  create_nsx_transport_zone ${nsx_master_controller_node_ip} ${nsx_cookie} ${nsx_zone_name}

  for i in 1 2 3 4 5 6 7 8 9; do
    if  [ ! -v $( eval "echo \${nsx_service_node_ip${i}}" ) ]; then
    nsx_service_node_ip=
    eval nsx_service_node_ip="\${nsx_service_node_ip${i}}"

    say "Setting cluster-manager for ${nsx_service_node_ip}."
    configure_nsx_service_node ${nsx_master_controller_node_ip} ${nsx_service_node_ip} ${nsx_user} ${nsx_pass} ${nsx_cookie}
    fi
  done
}

function configure_nsx_controller_node {
  nsx_master_controller_node_ip=$(getent hosts $1 | awk '{ print $1 }')
  nsx_controller_node_ip=$(getent hosts $2 | awk '{ print $1 }')
  nsx_user=$3
  nsx_pass=$4

  ssh_base="sshpass -p ${nsx_pass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  ${ssh_base} ${nsx_user}@${nsx_controller_node_ip} join control-cluster ${nsx_master_controller_node_ip}
}

function configure_nsx_service_node {
  nsx_master_controller_node_ip=$(getent hosts $1 | awk '{ print $1 }')
  nsx_service_node_ip=$(getent hosts $2 | awk '{ print $1 }')
  nsx_user=$3
  nsx_pass=$4
  nsx_cookie=$5

  ssh_base="sshpass -p ${nsx_pass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "

  ${ssh_base} ${nsx_user}@${nsx_service_node_ip} set switch manager-cluster ${nsx_master_controller_node_ip}

  say "Note: Creating Service Node ${nsx_service_node_ip} in Zone with UUID = ${nsx_transport_zone_uuid}"
  curl -L -k -b ${nsx_cookie} -X POST -d '{
    "credential": {
        "mgmt_address": "'"${nsx_service_node_ip}"'",
        "type": "MgmtAddrCredential"
    },
    "display_name": "mct-service-node",
    "transport_connectors": [
        {
            "ip_address": "'"${nsx_service_node_ip}"'",
            "type": "STTConnector",
            "transport_zone_uuid": "'"${nsx_transport_zone_uuid}"'"
        }
    ],
    "zone_forwarding": true
}' https://${nsx_master_controller_node_ip}/ws.v1/transport-node 2>&1 > /dev/null
}

function authenticate_nsx {
  nsx_master_controller_node_ip=$1
  nsx_cookie=$2
  nsx_user=$3
  nsx_pass=$4

  say "Authenticating against NSX controller"
  curl -L -k -c ${nsx_cookie} -X POST -d "username=${nsx_user}&password=${nsx_pass}" https://${nsx_master_controller_node_ip}/ws.v1/login
}

function check_nsx_cluster_health {
  nsx_master_controller_node_ip=$1
  nsx_cookie=$2

  say "Waiting for cluster to be healthy"
  while ! curl -L -sD - -k -b ${nsx_cookie}  https://${nsx_master_controller_node_ip}/ws.v1/control-cluster  | grep "HTTP/1.1 200"; do
    sleep 5
  done
  say "Cluster is healthy"
}

function create_nsx_transport_zone {
  nsx_master_controller_node_ip=$1
  nsx_cookie=$2
  nsx_zone_name=$3

  export nsx_transport_zone_uuid=$(curl -L -k -b ${nsx_cookie} -X POST -d "{ \"display_name\": \"${nsx_zone_name}\" }" https://${nsx_master_controller_node_ip}/ws.v1/transport-zone | sed -e 's/^.*"uuid": "//' -e 's/", .*$//')
}

function configure_kvm_host_in_nsx {
  nsx_master_controller_node_ip=$1
  nsx_cookie=$2
  kvm_host=$3
  kvm_host_ip=$(getent hosts $3 | awk '{ print $1 }')
  kvm_user=$4
  kvm_pass=$5

  SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

  say "Note: Getting KVM host certificate from ${kvm_host}"
  kvm_ovs_certificate=$(sshpass -p "${kvm_pass}" ssh ${SSH_OPTIONS} ${kvm_user}@${kvm_host} cat /etc/openvswitch/ovsclient-cert.pem | sed -z "s/\n/\\\\n/g")

  echo "Note: Creating KVM host (${kvm_host}) Transport Connector in Zone with UUID = ${nsx_transport_zone_uuid} "
  curl -L -k -b ${nsx_cookie} -X POST -d '{
    "credential": {
        "client_certificate": {
            "pem_encoded": "'"${kvm_ovs_certificate}"'"
        },
        "type": "SecurityCertificateCredential"
    },
    "display_name": "'"${kvm_host}"'",
    "integration_bridge_id": "br-int",
    "transport_connectors": [
        {
            "ip_address": "'"${kvm_host_ip}"'",
            "transport_zone_uuid": "'"${nsx_transport_zone_uuid}"'",
            "type": "STTConnector"
        }
    ]
}' https://${nsx_master_controller_node_ip}/ws.v1/transport-node 2>&1 > /dev/null
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

mkdir -p ${secondarystorage}

say "Deploying CloudStack DB"
deploy_cosmic_db ${cs1ip} ${cs1user} ${cs1pass}

say "Installing Marvin"
install_marvin "https://beta-nexus.mcc.schubergphilis.com/service/local/artifact/maven/redirect?r=snapshots&g=cloud.cosmic&a=cloud-marvin&v=LATEST&p=tar.gz"

say "Installing SystemVM templates"
systemtemplate="/data/templates/cosmic-systemvm.qcow2"
imagetype="qcow2"
install_systemvm_templates ${cs1ip} ${cs1user} ${cs1pass} ${secondarystorage} ${systemtemplate} ${hypervisor} ${imagetype}

if  [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then
  create_nsx_cluster
fi

for i in 1 2 3 4 5 6 7 8 9; do
  if  [ ! -v $( eval "echo \${cs${i}ip}" ) ]; then
    csuser=
    csip=
    cspass=
    eval csuser="\${cs${i}user}"
    eval csip="\${cs${i}ip}"
    eval cspass="\${cs${i}pass}"
    say "Configuring tomcat to load JaCoCo Agent on host ${csip}"
    configure_tomcat_to_load_jacoco_agent ${csip} ${csuser} ${cspass}

    say "Deploying CloudStack WAR on host ${csip}"
    deploy_cosmic_war ${csip} ${csuser} ${cspass} 'cosmic-client/target/cloud-client-ui-*.war'
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
    say "Installing Cosmic KVM Agent on host ${hvip}"
    install_kvm_packages ${hvip} ${hvuser} ${hvpass}

    say "Configuring agent to load JaCoCo Agent on host ${hvip}"
    configure_agent_to_load_jacococ_agent ${hvip} ${hvuser} ${hvpass}

    if  [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then
      configure_kvm_host_in_nsx ${nsx_master_controller_node_ip} ${nsx_cookie} ${hvip} ${hvuser} ${hvpass}
    fi
  fi
done
