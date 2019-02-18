#!/bin/bash

scripts_dir=$(dirname $0)
. ${scripts_dir}/../helper_scripts/cosmic/helperlib.sh

set -e

function usage {
  printf "Usage: %s: -m marvin_config -c to inform we're configuring CloudStack instead of Cosmic\n" $(basename $0) >&2
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
  set_ssh_base_and_scp_base ${hvpass}

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
  ${scp_base} cosmic-agent/src/test/resources/application.yml ${hvuser}@${hvip}:/etc/cosmic/agent/
  ${scp_base} -r cosmic-core/scripts/src/main/resources/scripts ${hvuser}@${hvip}:/opt/cosmic/agent/
  ${scp_base} cosmic-core/systemvm/dist/systemvm.iso ${hvuser}@${hvip}:/opt/cosmic/agent/vms/
  ${scp_base} cosmic-agent/bindir/cosmic-setup-agent.py ${hvuser}@${hvip}:/usr/bin/cosmic-setup-agent
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

  say "Cosmic KVM Agent installed in ${hvip}"
}

function deploy_cosmic_db {
  csip=$1
  csuser=$2
  cspass=$3

  wait_for_mysql_server ${csip}

  # SSH/SCP helpers
  set_ssh_base_and_scp_base ${cspass}

  ${ssh_base} ${csuser}@${csip} "mysql -u root -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;\""
  mysql -h ${csip} -u root < ${scripts_dir}/setup_files/create-cloud-db.sql

  # Download Flyway
  rm -rf /tmp/flyway*
  curl -o /tmp/flyway.tar.gz https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/4.2.0/flyway-commandline-4.2.0-linux-x64.tar.gz
  tar -xvf /tmp/flyway.tar.gz -C /tmp/

  # Do migration
  /tmp/flyway-4.2.0/flyway -url=jdbc:mariadb://${csip}:3306/cloud -user=cloud -password=cloud -encoding=UTF-8 -locations=filesystem:cosmic-core/cosmic-flyway/src migrate

  say "Cosmic DB deployed at ${csip}"
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
  set_ssh_base_and_scp_base ${cspass}

  tmpltsize=$(ls -l ${systemtemplate} | awk -F" " '{print $5}')

  if [[ "${hypervisor}" == "kvm" ]]; then
    sudo mkdir -p ${secondarystorage}/template/tmpl/1/3/
    sudo cp ${systemtemplate} ${secondarystorage}/template/tmpl/1/3/f327eecc-be53-4d80-9d43-adaf45467abd.qcow2

    sudo bash -c "cat >> ${secondarystorage}/template/tmpl/1/3/template.properties" << EOL
filename=f327eecc-be53-4d80-9d43-adaf45467abd.qcow2
description=SystemVM Template
checksum=
hvm=false
size=${tmpltsize}
qcow2=true
id=3
public=true
qcow2.filename=f327eecc-be53-4d80-9d43-adaf45467abd.qcow2
uniquename=routing-3
qcow2.virtualsize=${tmpltsize}
virtualsize=${tmpltsize}
qcow2.size=${tmpltsize}
EOL

   elif [[ "${hypervisor}" == "xenserver" ]]; then
    sudo mkdir -p ${secondarystorage}/template/tmpl/1/1/
    sudo cp ${systemtemplate} ${secondarystorage}/template/tmpl/1/1/9cc3c107-6d7b-11e7-8f09-5254001daa61.vhd

    sudo bash -c "cat >> ${secondarystorage}/template/tmpl/1/1/template.properties" << EOL
filename=9cc3c107-6d7b-11e7-8f09-5254001daa61.vhd
description=SystemVM Template
checksum=
hvm=false
size=${tmpltsize}
vhd=true
id=1
public=true
vhd.filename=9cc3c107-6d7b-11e7-8f09-5254001daa61.vhd
uniquename=routing-1
vhd.virtualsize=${tmpltsize}
virtualsize=${tmpltsize}
vhd.size=${tmpltsize}
EOL

  fi

  say "SystemVM templates installed"
}

function configure_tomcat_to_load_jacoco_agent {
  csip=$1
  csuser=$2
  cspass=$3

  # SSH/SCP helpers
  set_ssh_base_and_scp_base ${cspass}

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
  set_ssh_base_and_scp_base ${hvpass}

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
  set_ssh_base_and_scp_base ${cspass}

  # Extra configuration for Tomcat's webapp (namely adding /etc/cosmic/management to its classpath)
  ${scp_base} ${scripts_dir}/setup_files/client.xml ${csuser}@${csip}:/etc/tomcat/Catalina/localhost/

  # Extra configuration for Cosmic application
  ${ssh_base} ${csuser}@${csip} mkdir -p /etc/cosmic/management
  ${scp_base} ${scripts_dir}/setup_files/db.properties ${csuser}@${csip}:/etc/cosmic/management
  ${scp_base} ${scripts_dir}/setup_files/kafka.producer.properties ${csuser}@${csip}:/etc/cosmic/management
  # @TODO @FIXME Hardcoded to 2.3.0 because 2.4.0 doesn't work
  ${ssh_base} ${csuser}@${csip} 'curl -sL "https://beta-nexus.mcc.schubergphilis.com/service/local/artifact/maven/redirect?r=central&g=org.mariadb.jdbc&a=mariadb-java-client&v=2.3.0" -o /usr/share/java/tomcat/mariadb-java-client-latest.jar'
  ${scp_base} ${scripts_dir}/setup_files/context.xml ${csuser}@${csip}:/etc/tomcat
  ${ssh_base} ${csuser}@${csip} "sed -i \"s/cluster.node.IP=/cluster.node.IP=${csip}/\" /etc/cosmic/management/db.properties"

  ${ssh_base} ${csuser}@${csip} mkdir -p /var/log/cosmic/management
  ${ssh_base} ${csuser}@${csip} chown -R tomcat /var/log/cosmic
  ${scp_base} ${war_file} ${csuser}@${csip}:~tomcat/webapps/client.war
  ${ssh_base} ${csuser}@${csip} service tomcat start &> /dev/null

  say "WAR deployed"
}

function create_nsx_cluster {
  set_ssh_base_and_scp_base ${cspass}

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
  echo "New master ip after authenticating ${nsx_master_controller_node_ip}"

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

function setup_nsx_cosmic {
  csip=$1
  isolationmethod=$2
  export NSX_COSMIC_SCRIPT=/tmp/nsx_cosmic_${csip}.sh
  say "Generating script for setting up NSX controller in Cosmic"
  echo "#!/usr/bin/env bash" > ${NSX_COSMIC_SCRIPT}
  echo "" >> ${NSX_COSMIC_SCRIPT}
  echo "set -x" >> ${NSX_COSMIC_SCRIPT}
  echo "next_host_id=\$(mysql -h ${csip} -u cloud -pcloud cloud -e \"SELECT MAX(id) +1 FROM host;\" -s)" >> ${NSX_COSMIC_SCRIPT}
  echo "nsx_cosmic_uuid=$(uuidgen)" >> ${NSX_COSMIC_SCRIPT}
  echo "nsx_cosmic_controller_uuid=$(uuidgen)" >> ${NSX_COSMIC_SCRIPT}
  echo "nsx_cosmic_controller_guid=$(uuidgen)" >> ${NSX_COSMIC_SCRIPT}
  echo "nsx_transzone_uuid=${nsx_transport_zone_uuid}" >> ${NSX_COSMIC_SCRIPT}
  echo "nsx_master_controller_node_ip=${nsx_master_controller_node_ip}" >> ${NSX_COSMIC_SCRIPT}

  echo "nsx_query1=\"INSERT INTO host (id, name, uuid, status, type, private_ip_address, private_netmask, private_mac_address, storage_ip_address, storage_netmask, storage_mac_address, storage_ip_address_2, storage_mac_address_2, storage_netmask_2, cluster_id, public_ip_address, public_netmask, public_mac_address, proxy_port, data_center_id, pod_id, cpu_sockets, cpus, url, fs_type, hypervisor_type, hypervisor_version, ram, resource, version, parent, total_size, capabilities, guid, available, setup, dom0_memory, last_ping, mgmt_server_id, disconnected, created, removed, update_count, resource_state, owner, lastUpdated, engine_state) VALUES	(\${next_host_id}, 'Nicira Controller - \${nsx_master_controller_node_ip}', '\${nsx_cosmic_controller_uuid}', 'Down', 'L2Networking', '', NULL, NULL, '', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'com.cloud.network.resource.NiciraNvpResource', '5.2.0.1-SNAPSHOT', NULL, NULL, NULL, '\${nsx_cosmic_controller_guid}', 1, 0, 0, 0, NULL, NULL, NOW(), NULL, 0, 'Enabled', NULL, NULL, 'Disabled');\" " >> ${NSX_COSMIC_SCRIPT}
  echo "mysql -h ${csip} -u cloud -pcloud cloud -e \"\${nsx_query1}\"" >> ${NSX_COSMIC_SCRIPT}

  echo "nsx_query2=\"INSERT INTO external_nicira_nvp_devices (uuid, physical_network_id, provider_name, device_name, host_id) VALUES ('\${nsx_cosmic_controller_uuid}', 201, 'NiciraNvp', 'NiciraNvp', \${next_host_id});\"" >> ${NSX_COSMIC_SCRIPT}
  echo "mysql -h ${csip} -u cloud -pcloud cloud -e \"\${nsx_query2}\"" >> ${NSX_COSMIC_SCRIPT}

  echo "nsx_query3=\"INSERT INTO host_details (host_id, name, value) VALUES (\${next_host_id}, 'transportzoneuuid', '\${nsx_transzone_uuid}'), (\${next_host_id}, 'physicalNetworkId', '201'), (\${next_host_id}, 'adminuser', 'admin'), (\${next_host_id}, 'ip', '\${nsx_master_controller_node_ip}'), (\${next_host_id}, 'name', 'Nicira Controller - \${nsx_master_controller_node_ip}'), (\${next_host_id}, 'transportzoneisotype', '${isolationmethod}'), (\${next_host_id}, 'guid', '\${nsx_cosmic_controller_guid}'),(\${next_host_id}, 'zoneId', '1'), (\${next_host_id}, 'adminpass', 'admin'),(\${next_host_id}, 'niciranvpdeviceid', '1');\"" >> ${NSX_COSMIC_SCRIPT}
  echo "mysql -h ${csip} -u cloud -pcloud cloud -e \"\${nsx_query3}\"" >> ${NSX_COSMIC_SCRIPT}
}

function configure_nsx_controller_node {
  nsx_master_controller_node_ip=$(getent hosts $1 | awk '{ print $1 }')
  nsx_controller_node_ip=$(getent hosts $2 | awk '{ print $1 }')
  nsx_user=$3
  nsx_pass=$4

  set_ssh_base_and_scp_base ${nsx_pass}

  ${ssh_base} ${nsx_user}@${nsx_controller_node_ip} join control-cluster ${nsx_master_controller_node_ip}
}

function configure_nsx_service_node {
  nsx_master_controller_node_ip=$(getent hosts $1 | awk '{ print $1 }')
  nsx_service_node=$2
  nsx_service_node_ip=$(getent hosts ${nsx_service_node} | awk '{ print $1 }')
  nsx_user=$3
  nsx_pass=$4
  nsx_cookie=$5

  set_ssh_base_and_scp_base ${nsx_pass}


  ${ssh_base} ${nsx_user}@${nsx_service_node_ip} set switch manager-cluster ${nsx_master_controller_node_ip}

  say "Note: Creating Service Node ${nsx_service_node_ip} in Zone with UUID = ${nsx_transport_zone_uuid}"
  curl -L -k -b ${nsx_cookie} -X POST -d '{
    "credential": {
        "mgmt_address": "'"${nsx_service_node_ip}"'",
        "type": "MgmtAddrCredential"
    },
    "display_name": "'"${nsx_service_node}"'",
    "transport_connectors": [
        {
            "ip_address": "'"${nsx_service_node_ip}"'",
            "type": "VXLANConnector",
            "transport_zone_uuid": "'"${nsx_transport_zone_uuid}"'"
        },
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

  say "Master ip before we start: ${nsx_master_controller_node_ip}"
  say "Testing all controllers.."

  set +e

  while :; do
      for i in 1 2 3 4 5 6 7 8 9; do
        if  [ ! -v $( eval "echo \${nsx_controller_node_ip${i}}" ) ]; then
          nsx_controller_node_ip=
          eval nsx_controller_node_ip="\${nsx_controller_node_ip${i}}"
          say "Checking to see if ${nsx_controller_node_ip} is master"
          say "Authenticating against NSX controller ${nsx_controller_node_ip}"
          curl -L -k -c ${nsx_cookie} -X POST -d "username=${nsx_user}&password=${nsx_pass}" https://${nsx_controller_node_ip}/ws.v1/login
          is_master=$(curl -L -sD - -k -b ${nsx_cookie}  https://${nsx_controller_node_ip}/ws.v1/control-cluster | egrep 'HTTP/1.1 200')
          if [ $? -gt 0 ]; then
            say "Controller ${nsx_controller_node_ip} DOES NOT respond with 200 so this is NOT our master!"
            say "Output: ${is_master}"
          else
            say "Controller ${nsx_controller_node_ip} responds with 200 so this is our master!"
            say "Output: ${is_master}"
            export nsx_master_controller_node_ip=$(getent hosts ${nsx_controller_node_ip} | awk '{ print $1 }')
            say "New master ip is ${nsx_master_controller_node_ip}"
            break 2
          fi
        fi
      done
      say "Master not yet found, sleeping 10 sec and trying again.."
      sleep 10
  done

  set -e

  say "Authenticating against master NSX controller"
  curl -L -k -c ${nsx_cookie} -X POST -d "username=${nsx_user}&password=${nsx_pass}" https://${nsx_master_controller_node_ip}/ws.v1/login
  echo "New master ip ${nsx_master_controller_node_ip}"
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

  SSH_OPTIONS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

  say "Generate OVS certificates on ${kvm_host}"
  sshpass -p "${kvm_pass}" ssh ${SSH_OPTIONS} ${kvm_user}@${kvm_host} "cd /etc/openvswitch; ovs-pki req ovsclient; ovs-pki self-sign ovsclient; ovs-vsctl -- --bootstrap set-ssl /etc/openvswitch/ovsclient-privkey.pem /etc/openvswitch/ovsclient-cert.pem /etc/openvswitch/vswitchd.cacert"
  sshpass -p "${kvm_pass}" ssh ${SSH_OPTIONS} ${kvm_user}@${kvm_host} "chown openvswitch:openvswitch /etc/openvswitch/*"
  sshpass -p "${kvm_pass}" ssh ${SSH_OPTIONS} ${kvm_user}@${kvm_host} "systemctl restart openvswitch"

  say "Note: Getting KVM host certificate from ${kvm_host}"
  kvm_ovs_certificate=$(sshpass -p "${kvm_pass}" ssh ${SSH_OPTIONS} ${kvm_user}@${kvm_host} cat /etc/openvswitch/ovsclient-cert.pem | sed -z "s/\n/\\\\n/g")

  say "Note: Creating KVM host (${kvm_host}) Transport Connector in Zone with UUID = ${nsx_transport_zone_uuid} "
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
            "type": "VXLANConnector"
        },
        {
            "ip_address": "'"${kvm_host_ip}"'",
            "transport_zone_uuid": "'"${nsx_transport_zone_uuid}"'",
            "type": "STTConnector"
        }
    ]
    }' https://${nsx_master_controller_node_ip}/ws.v1/transport-node 2>&1 > /dev/null

   say "Setting NSX manager of ${kvm_host} to ${nsx_master_controller_node_ip}"
   sshpass -p "${kvm_pass}" ssh ${SSH_OPTIONS} ${kvm_user}@${kvm_host}  "ovs-vsctl set-manager ssl:${nsx_master_controller_node_ip}:6632"
}


function configure_xenserver_host_in_nsx {
  nsx_master_controller_node_ip=$1
  nsx_cookie=$2
  xen_host=$3
  xen_host_ip=$(getent hosts $3 | awk '{ print $1 }')
  xen_user=$4
  xen_pass=$5

  say "Waiting for Xapi to be ready"
  wait_for_port ${xen_host} 443 tcp
  wait_for_port ${xen_host} 22 tcp
  xen_integration_bridge_uuid=$(${ssh_base} ${xen_user}@${xen_host} "/opt/xensource/bin/xe network-list name-label=br-int --minimal | tr -d '\n'")

  if [ -z "${xen_integration_bridge_uuid}" ]; then
    say "Error: No integration bridge UUID found: ${xen_integration_bridge_uuid}"
    exit 1
  fi

  echo "Note: Creating XenServer host (${xen_host}) Transport Connector in Zone with UUID = ${nsx_transport_zone_uuid} "
  curl -L -k -b ${nsx_cookie} -X POST -d '{
    "credential": {
      "mgmt_address": "'"${xen_host_ip}"'",
      "type": "MgmtAddrCredential"
    },
    "display_name": "'"${xen_host}"'",
    "integration_bridge_id": "'"${xen_integration_bridge_uuid}"'",
    "transport_connectors": [
        {
            "ip_address": "'"${xen_host_ip}"'",
            "transport_zone_uuid": "'"${nsx_transport_zone_uuid}"'",
            "type": "VXLANConnector"
        },
        {
            "ip_address": "'"${xen_host_ip}"'",
            "transport_zone_uuid": "'"${nsx_transport_zone_uuid}"'",
            "type": "STTConnector"
        }
    ]
    }' https://${nsx_master_controller_node_ip}/ws.v1/transport-node
}

# Options
cloudstack_deploy_mode=0
while getopts 'cm:' OPTION
do
  case $OPTION in
  m)    marvin_config="$OPTARG"
        ;;
  c)    cloudstack_deploy_mode=1
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

marvin_build_and_install "$PWD/cosmic-marvin"

mkdir -p ${secondarystorage}

say "Deploying Cosmic DB"
if [ ${cloudstack_deploy_mode} -eq 0 ]; then
    say "Cosmic DB that is build here is also compatible with CloudStack, as the base is CloudStack 4.0"
fi
deploy_cosmic_db ${cs1ip} ${cs1user} ${cs1pass}

say "Installing Cosmic SystemVM templates"
if [[ "${hypervisor}" == "kvm" ]]; then
  systemtemplate="/data/templates/cosmic-systemvm.qcow2"
  imagetype="qcow2"
 elif [[ "${hypervisor}" == "xenserver" ]]; then
  systemtemplate="/data/templates/cosmic-systemvm.vhd"
  imagetype="vhd"
fi
install_systemvm_templates ${cs1ip} ${cs1user} ${cs1pass} ${secondarystorage} ${systemtemplate} ${hypervisor} ${imagetype}

if  [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then
  create_nsx_cluster
fi

if [ ${cloudstack_deploy_mode} -eq 0 ]; then
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

        say "Deploying Cosmic WAR on host ${csip}"
        deploy_cosmic_war ${csip} ${csuser} ${cspass} 'cosmic-client/target/cloud-client-ui-*.war'
      fi
    done
fi
host_count=0
master_address=0
master_username=0
master_password=0
for i in 1 2 3 4 5 6 7 8 9; do
  if  [ ! -v $( eval "echo \${hvip${i}}" ) ]; then
    hvuser=
    hvip=
    hvpass=
    eval hvuser="\${hvuser${i}}"
    eval hvip="\${hvip${i}}"
    eval hvpass="\${hvpass${i}}"
    # SSH/SCP helpers for xen password
    set_ssh_base_and_scp_base ${hvpass}

    if [[ "${hypervisor}" == "kvm" ]]; then
        if [ ${cloudstack_deploy_mode} -eq 0 ]; then
          say "Installing Cosmic KVM Agent on host ${hvip}"
          install_kvm_packages ${hvip} ${hvuser} ${hvpass}

          say "Configuring agent to load JaCoCo Agent on host ${hvip}"
          configure_agent_to_load_jacococ_agent ${hvip} ${hvuser} ${hvpass}

          if [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then
            say "Adding KVM ${hvip} to NSX"
            configure_kvm_host_in_nsx ${nsx_master_controller_node_ip} ${nsx_cookie} ${hvip} ${hvuser} ${hvpass}
          fi
       else
          say "Installing CloudStack KVM Agent on host ${hvip} is not yet implemented!"
       fi
    elif [[ "${hypervisor}" == "xenserver" ]]; then
      ${ssh_base} ${hvuser}@${hvip} sed -i "s/HOSTNAME=.*/HOSTNAME=${hvip}/g" /etc/sysconfig/network
      say "Creating .ssh folder for root"
      wait_for_port ${hvip} 22 tcp
      ${ssh_base} ${hvuser}@${hvip} "mkdir -p /root/.ssh"

      ((host_count++)) || true
      if [[ host_count -eq 1 ]]; then
        master_address=${hvip}
        master_username=${hvuser}
        master_password=${hvpass}

        say "Creating networks on XenServer on poolmaster ${master_address}"
        NETUUID=$(${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe network-create name-label=\"br-int\" --minimal | tr -d '\n'")
        STTUUID=$(${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe network-list bridge=\"xenbr0\" --minimal | tr -d '\n'")
        PIFUUID=$(${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe pif-list network-uuid=${STTUUID} host-name-label=${hvip} --minimal | tr -d '\n'")
        TUNUUID=$(${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe tunnel-create pif-uuid=${PIFUUID} network-uuid=${NETUUID} | tr -d '\n'")
        ${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe network-param-set uuid=${NETUUID} other-config:vswitch-disable-in-band=true other-config:vswitch-controller-failmode=secure"

      elif [[ host_count -gt 1 ]]; then
        say "More than one XenServer host detected, waiting for ${hvip} host to be ready..."
        wait_for_port ${master_address} 443 tcp
        wait_for_port ${hvip} 443 tcp
        say "Waiting for SSH to be up at ${hvip}"
        wait_for_port ${hvip} 22 tcp
        say "Setting ${master_address} as the master XenServer of ${hvip}"
        ${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe pool-join master-address=${master_address} master-username=${master_username} master-password=${master_password}"
        say "Allowing the XenServers to connect"
        sleep 10
      fi
      if [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then
        say "Adding XenServer ${hvip} to NSX"
        configure_xenserver_host_in_nsx ${nsx_master_controller_node_ip} ${nsx_cookie} ${hvip} ${hvuser} ${hvpass}
        ${ssh_base} ${hvuser}@${hvip} "/opt/xensource/bin/xe pool-set-vswitch-controller address=${nsx_master_controller_node_ip}"
      fi
    fi
  fi
done

if  [ ! -v $( eval "echo \${nsx_controller_node_ip1}" ) ]; then

  isolationmethod="vxlan"
  if [ ${cloudstack_deploy_mode} -eq 1 ]; then
     isolationmethod="stt"
  fi

  setup_nsx_cosmic ${csip} ${isolationmethod}
fi
