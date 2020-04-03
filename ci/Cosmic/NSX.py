from __future__ import print_function

import socket
import time

import json

import mysql.connector
import requests
import uuid
from jsonpath_ng import parse
from mysql.connector import Error
from . import Base


class NSX(Base.Base):
    def __new__(cls, marvin_config=None, **kwargs):
        """Create new instance if niciraNvp is present in the marvin_config

        :param marvin_config: Marvin config file
        """
        try:
            tmpbuf = open(marvin_config, "r").read()
            if 'niciraNvp' in tmpbuf:
                return object.__new__(cls)
        except IOError:
            pass
        return None

    def __init__(self, marvin_config=None, debug=None):
        """Initializes NSX class

        :param marvin_config: Marvin config file
        :param debug: Output debug information
        """
        super(NSX, self).__init__(marvin_config=marvin_config, debug=debug)
        self.nsx_zone_name = 'mct-zone'
        self.nsx_user = 'admin'
        self.nsx_pass = 'admin'
        self.session = requests.session()
        master = parse('niciraNvp[*].controllerNodes[0]').find(self.config)
        self.master = socket.gethostbyname(master[0].value)
        self.transport_zone_uuid = None
        self.cloud_db = mysql.connector.connect(
            database='cloud',
            host=self.config['dbSvr']['dbSvr'],
            port=self.config['dbSvr']['port'],
            username=self.config['dbSvr']['user'],
            password=self.config['dbSvr']['passwd']
        )

    def create_cluster(self):
        """Create NSX cluster"""
        self.configure_controller_node()
        self.authenticate()
        self.check_cluster_health()
        self.create_transport_zone()
        for node in parse("niciraNvp[*].controllerNodes[*]").find(self.config):
            self.configure_service_node(node=node.value)

    def setup_cosmic(self, isolation_mode=None):
        """Setup NSX in Cosmic"""
        cosmic_controller_uuid = uuid.uuid4()
        cosmic_controller_guid = uuid.uuid4()

        cloud_cursor = self.cloud_db.cursor()
        try:
            cloud_cursor.execute("SELECT MAX(id) +1 FROM host;")
            next_host_id = cloud_cursor.fetchone()[0]
            nsx_query = ("INSERT INTO host (id,name,uuid,status,type,private_ip_address,private_netmask,"
                         "private_mac_address,storage_ip_address,storage_netmask,storage_mac_address,"
                         "storage_ip_address_2,storage_mac_address_2,storage_netmask_2,cluster_id,public_ip_address,"
                         "public_netmask,public_mac_address,proxy_port,data_center_id,pod_id,cpu_sockets,cpus,url,"
                         "fs_type,hypervisor_type,hypervisor_version,ram,resource,version,parent,total_size,"
                         "capabilities,guid,available,setup,dom0_memory,last_ping,mgmt_server_id,disconnected,"
                         "created,removed,update_count,resource_state,owner,lastUpdated,engine_state) VALUES "
                         "(%s,'Nicira Controller - %s','%s','Down','L2Networking','',NULL,NULL,'',NULL,NULL,"
                         "NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,1,NULL,NULL,NULL,NULL,NULL,NULL,NULL,0,"
                         "'com.cloud.network.resource.NiciraNvpResource','5.2.0.1-SNAPSHOT',NULL,NULL,NULL,"
                         "'%s',1,0,0,0,NULL,NULL,NOW(),NULL,0,'Enabled',NULL,NULL,'Disabled');" %
                         (next_host_id, self.master, cosmic_controller_uuid, cosmic_controller_guid))
            cloud_cursor.execute(nsx_query)
            self.cloud_db.commit()

            nsx_query = ("INSERT INTO external_nicira_nvp_devices (uuid,physical_network_id,provider_name,device_name,"
                         "host_id) VALUES ('${nsx_cosmic_controller_uuid}',201,'NiciraNvp','NiciraNvp',%s);" %
                         next_host_id)
            cloud_cursor.execute(nsx_query)
            self.cloud_db.commit()

            nsx_query = ("INSERT INTO host_details (host_id, name, value) VALUES ({0},'transportzoneuuid','{1}'), ({0},"
                         "'physicalNetworkId','201'),({0},'adminuser','admin'),({0},'ip','{2}'),({0},'name',"
                         "'Nicira Controller - {2}'),({0},'transportzoneisotype','{3}'),({0},'guid','{4}'),({0},"
                         "'zoneId','1'),({0},'adminpass','admin'),({0},'niciranvpdeviceid','1');".format(
                          next_host_id, self.transport_zone_uuid, self.master, isolation_mode, cosmic_controller_guid))
            cloud_cursor.execute(nsx_query)
            self.cloud_db.commit()
        except Error as e:
            print("==> Error executing queries: ", e)
        finally:
            if self.cloud_db.is_connected():
                cloud_cursor.close()

    def configure_controller_node(self):
        """Let NSX node join cluster"""
        for ctrlnode in parse('niciraNvp[*].controllerNodes[*]').find(self.config):
            cmd = "join control-cluster %s" % self.master
            self._ssh(hostname=ctrlnode.value, username=self.nsx_user, password=self.nsx_pass, cmd=cmd)

    def configure_service_node(self, node=None):
        """Configure NSX transport connectors for node"""
        node_ip = socket.gethostbyname(node)
        data = {"credential": {"mgmt_address": node_ip, "type": "MgmtAddrCredential"},
                "display_name": node,
                "transport_connectors": [{
                    "ip_address": node_ip,
                    "type": "VXLANConnector",
                    "transport_zone_uuid": self.transport_zone_uuid
                }, {
                    "ip_address": node_ip,
                    "type": "STTConnector",
                    "transport_zone_uuid": self.transport_zone_uuid
                }],
                "zone_forwarding": True}
        _resp = self.session.post("https://%s/ws.v1/transport-node" % self.master, data=json.dumps(data))

    def authenticate(self):
        """Get NSX authentication cookie"""
        retries = 10
        done = False
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        print("==> Master ip before we start: %s\nTesting all controllers.." % self.master)

        while retries > 0 and not done:
            for ctrlr in parse('niciraNvp[*].controllerNodes[*]').find(self.config):
                print("==> Checking to see if %s is master" % ctrlr.value)
                print("==> Authenticating against NSX controller %s" % ctrlr.value)
                _resp = self.session.post("https://%s/ws.v1/login" % ctrlr.value,
                                          data="username=%s&password=%s" % (self.nsx_user, self.nsx_pass),
                                          verify=False, headers=headers)
                resp = self.session.get("https://%s/ws.v1/control-cluster" % ctrlr.value, verify=False)
                if resp.status_code == 200:
                    print("==> Controller %s responds with 200 so this is our master!" % ctrlr.value)
                    print("==> Output: %s" % resp.content)
                    self.master = socket.gethostbyname(ctrlr.value)
                    done = True
                    break
                print("==> Controller %s DOES NOT respond with 200 so is NOT our master!" % ctrlr.value)
                print("==> Output: %s" % resp.content)
            else:
                retries -= 1
                print("==> Master not yet found, sleeping for 10 sec and trying again..")
                time.sleep(10)
        print("==> Authenticating against master NSX controller..")
        _resp = self.session.post("https://%s/ws.v1/login" % self.master,
                                  data="username=%s&password=%s" % (self.nsx_user, self.nsx_pass),
                                  verify=False, headers=headers)
        if _resp.ok:
            print("==> New master ip %s" % self.master)
        else:
            print("==> Got %s as response!!" % _resp.status_code)

    def check_cluster_health(self):
        """Check NSX cluster health"""
        print("==> Waiting for cluster to be healthy")
        while True:
            resp = self.session.get("https://%s/ws.v1/control-cluster" % self.master)
            if resp.ok:
                break
            time.sleep(5)
        print("==> Cluster is healthy")

    def create_transport_zone(self):
        """Configure NSX transport zone"""
        data = {"display_name": self.nsx_zone_name}
        resp = self.session.post("https://%s/ws.v1/transport-zone" % self.master, data=json.dumps(data))
        if resp.ok:
            self.transport_zone_uuid = json.loads(resp.content)['uuid']

    def get_transport_zone(self):
        """Get NSX transport zone"""
        _resp = self.session.get("https://%s/ws.v1/transport-zone" % self.master)

    def configure_kvm_host(self):
        zones = parse('zones[*]').find(self.config)
        for zone in zones:
            hosts = parse('pods[*].clusters[*].hosts[*]').find(zone)
            for host in hosts:
                hostname = host.value['url'].split('/')[-1]
                host_ip = socket.gethostbyname(hostname)
                connection = {'hostname': hostname, 'username': host.value['username'],
                              'password': host.value['password']}
                cmds = [
                    ("cd /etc/openvswitch;"
                     "ovs-pki req ovsclient;"
                     "ovs-pki self-sign ovsclient;"
                     "ovs-vsctl -- --bootstrap set-ssl /etc/openvswitch/ovsclient-privkey.pem /etc/openvswitch/ovsclient-cert.pem /etc/openvswitch/vswitchd.cacert"),
                    "chown openvswitch:openvswitch /etc/openvswitch/*",
                    "systemctl restart openvswitch"
                ]

                print("==> Generate OVS certificates on %s" % hostname)
                for cmd in cmds:
                    self._ssh(cmd=cmd, **connection)

                print("==> Getting KVM host certificate from %s" % hostname)
                exitcode, stdout, stderr = self._ssh(
                    cmd='cat /etc/openvswitch/ovsclient-cert.pem | sed -z "s/\\n/\\\\n/g"', **connection)
                if exitcode == 0:
                    print("==> Create KVM host %s Transport Connector in Zone with UUID=%s" % (
                     hostname, self.transport_zone_uuid))
                    data = {"credential": {
                        "client_certificate": {
                            "pem_encoded": "".join(stdout)
                        },
                        "type": "SecurityCertificateCredential"
                    },
                        "display_name": hostname,
                        "integration_bridge_id": "br-int",
                        "transport_connectors": [
                            {
                                "ip_address": host_ip,
                                "transport_zone_uuid": self.transport_zone_uuid,
                                "type": "VXLANConnector"
                            },
                            {
                                "ip_address": host_ip,
                                "transport_zone_uuid": self.transport_zone_uuid,
                                "type": "STTConnector"
                            }
                        ]
                    }
                    _resp = self.session.post("https://%s/ws.v1/transport-node" % self.master, data=json.dumps(data))
                    if _resp.ok:
                        print("==> Setting NSX manager of %s to %s" % (hostname, self.master))
                        self._ssh(cmd="ovs-vsctl set-manager ssl:%s:6632" % self.master, **connection)
                    else:
                        print("==> Error setting up transport connector for %s" % hostname)

    def add_connectivy_to_offerings(self):
        """Add network offering to Cosmic with NSX connectivity"""
        cloud_cursor = self.cloud_db.cursor()
        try:
            cloud_cursor.execute(
                "INSERT IGNORE INTO cloud.network_offering_service_map (network_offering_id, service, provider, created) "
                "(SELECT DISTINCT X.network_offering_id, 'Connectivity', 'NiciraNvp', X.created FROM cloud.network_offering_service_map X);")
            cloud_cursor.execute(
                "INSERT IGNORE INTO cloud.vpc_offering_service_map (vpc_offering_id, service, provider, created) "
                "(SELECT DISTINCT X.vpc_offering_id, 'Connectivity', 'NiciraNvp', X.created FROM cloud.vpc_offering_service_map X);")
            cloud_cursor.execute(
                "INSERT IGNORE INTO cloud.network_offering_service_map (network_offering_id, service, provider, created) "
                "(SELECT DISTINCT X.id, 'Connectivity', 'NiciraNvp', X.created FROM cloud.network_offerings X "
                "WHERE name IN ('DefaultPrivateGatewayNetworkOffering', 'DefaultPrivateGatewayNetworkOfferingSpecifyVlan', 'DefaultSyncNetworkOffering'));")
        except Error as e:
            print("==> Error executing MariaDB query: ", e)
        finally:
            if self.cloud_db.is_connected():
                cloud_cursor.close()
