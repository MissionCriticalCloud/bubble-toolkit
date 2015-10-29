#!/usr/bin/python

#      Copyright 2015, Schuberg Philis BV
#
#      Licensed to the Apache Software Foundation (ASF) under one
#      or more contributor license agreements.  See the NOTICE file
#      distributed with this work for additional information
#      regarding copyright ownership.  The ASF licenses this file
#      to you under the Apache License, Version 2.0 (the
#      "License"); you may not use this file except in compliance
#      with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#      Unless required by applicable law or agreed to in writing,
#      software distributed under the License is distributed on an
#      "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#      KIND, either express or implied.  See the License for the
#      specific language governing permissions and limitations
#      under the License.

#      Script to deploy VMs locally on Qemu/KVM
#      Written by Remi Bergsma, Schuberg Philis
#      remi@remi.nl

import libvirt
import xml.etree.ElementTree as ET
import sys
import getopt
import os.path
import ConfigParser
import shutil
from jinja2 import Template
import subprocess
import json
import socket
import re
from multiprocessing.dummy import Pool as ThreadPool
import os

# Colored terminals
try:
    from clint.textui import colored
except:
    print "Error: Please install clint library to support color in the terminal:"
    print "       pip install clint"
    sys.exit(1)

# Handle the arguments
def handleArguments(argv):
    global DEBUG
    DEBUG = 0
    global DRYRUN
    DRYRUN = 1
    global FORCE
    FORCE = 0
    global deploy_role
    deploy_role = ''
    global deploy_vm
    deploy_vm = ''
    global deploy_cloud
    deploy_cloud = ''
    global deploy_marvin
    deploy_marvin = ''
    global digit
    digit = ''
    global delete
    delete = ''
    global display_state
    display_state = False

    # Usage message
    help = "Usage: ./" + os.path.basename(__file__) + ' [options]' + \
        '\n  --deploy-role -r \t\tDeploy VM with this role' + \
        '\n  --deploy-vm -n \t\tDeploy VM with this name' + \
        '\n  --deploy-cloud -c \t\tDeploy group of VMs to build a cloud' + \
        '\n  --deploy-marvin -m \t\tDeploy hardware from this Marvin DataCenter configuration' + \
        '\n  --digit -d \t\t\tDigit to append to the role-name instead of the next available' + \
        '\n  --status -s \t\t\tDisplay status of your VMs' + \
        '\n  --delete \t\t\tOnly delete the specified VM (needs --digit) or Marvin config' + \
        '\n  --force \t\t\tDelete VMs when they already exist' + \
        '\n  --debug \t\t\tEnable debug mode'

    try:
        opts, args = getopt.getopt(
            argv, "hr:c:d:m:n:s", [
                "deploy-role=", "deploy-vm=", "deploy-cloud=", "deploy-marvin=", "digit=", "delete", "status", "debug", "force"])
    except getopt.GetoptError as e:
        print "Error: " + str(e)
        print help
        sys.exit(2)

    if len(opts) == 0:
        print help
        sys.exit(2)

    for opt, arg in opts:
        print "processing option " + opt + " arg " + arg
        if opt == '-h':
            print help
            sys.exit()
        elif opt in ("-r", "--deploy-role"):
            deploy_role = arg
        elif opt in ("-n", "--deploy-vm"):
            deploy_vm = arg
        elif opt in ("-c", "--deploy-cloud"):
            deploy_cloud = arg
        elif opt in ("-m", "--deploy-marvin"):
            deploy_marvin = arg
        elif opt in ("-d", "--digit"):
            digit = arg
        elif opt in ("-s", "--status"):
            display_state = True
        elif opt in ("--debug"):
            DEBUG = 1
        elif opt in ("--force"):
            FORCE = 1
        elif opt in ("--delete"):
            delete = 1

# Parse arguments
if __name__ == "__main__":
    handleArguments(sys.argv[1:])

# Deploy local KVM class
class kvm_local_deploy:

    # Init function
    def __init__(self, debug=0, dryrun=0, force=0, marvin_config=''):
        self.DEBUG = debug
        self.DRYRUN = dryrun
        self.FORCE = force
        self.marvin_config = marvin_config
        self.marvin_data = False
        # we can run as a user in the libvirt group
        #self.check_root()
        self.configfile = os.path.dirname(os.path.realpath(__file__)) + '/config'
        self.config_data = {}
        try:
            self.conn = libvirt.open('qemu:///system')
        except Exception, e:
            print "ERROR: Could not connect to Qemu!"
            sys.exit(1)

        self.print_welcome()
        self.read_config_file(self.configfile)

    # Check for root permissions
    def check_root(self):
        if not os.geteuid() == 0:
            print "ERROR: Script must be run as root'"
            sys.exit(1)

    # Read our own config file for settings
    def read_config_file(self, configfile):
        config = ConfigParser.RawConfigParser()
        config.read(self.configfile)
        try:
            self.config_data = self.get_config_section(self.configfile, 'mct')
            self.config_data['base_dir'] = os.path.dirname(os.path.realpath(__file__))
        except:
            print "Error: Cannot read or parse mctDeploy config file '" + self.configfile + "'"
            print "Hint: Setup the local config file 'config', using 'config.sample' as a starting point. See documentation."
            sys.exit(1)

    # Read section from config file
    def get_config_section(self, configfile, section):
        config = ConfigParser.RawConfigParser()
        try:
            config.read(configfile)
            confdict = {}
            options = config.options(section)
        except:
            return False
        for option in options:
            try:
                confdict[option] = config.get(section, option)
                if confdict[option] == -1:
                    DebugPrint("skip: %s" % option)
            except:
                print("exception on %s!" % option)
                confdict[option] = None
        return confdict

    # Print welcome message
    def print_welcome(self):
        print colored.green("Welcome to KVM local Deploy for MCT")
        hostname = self.conn.getHostname()
        print "Note: We're connected to " + hostname
        print

    # Get offering details
    def get_offering(self, offering_name):
        if self.offering_exists(offering_name):
            offering_config = self.config_data['base_dir'] + "/" + self.config_data['offering_dir'] + "/" + offering_name + '.conf'
            return self.get_config_section(offering_config, 'offering')
        else:
            print "ERROR: Offering with name " + offering_name + " does not exist!"
            sys.exit(1)

    # Get role details
    def get_role(self, role_name):
        if self.role_exists(role_name):
            role_config = self.config_data['base_dir'] + "/" + self.config_data['role_dir'] + "/" + role_name + '.conf'
            return self.get_config_section(role_config, 'role')
        else:
            return False

    # Check if offering definition exists
    def offering_exists(self, offering_name):
        offering_config = self.config_data['base_dir'] + "/" + self.config_data['offering_dir'] + "/" + offering_name + '.conf'
        if os.path.isfile(offering_config):
            return True
        else:
            return False

    # Check if role definition exists
    def role_exists(self, role_name):
        role_config = self.config_data['base_dir'] + "/" + self.config_data['role_dir'] + "/" + role_name + '.conf'
        if os.path.isfile(role_config):
            return True
        else:
            return False

    # Get cloud details
    def get_cloud(self, cloud_name):
        if self.cloud_exists(cloud_name):
            cloud_config = self.config_data['base_dir'] + "/" + self.config_data['cloud_dir'] + "/" + cloud_name + '.conf'
            return self.get_config_section(cloud_config, 'cloud')
        else:
            return False

    # Check if cloud definition exists
    def cloud_exists(self, cloud_name):
        cloud_config = self.config_data['base_dir'] + "/" + self.config_data['cloud_dir'] + "/" + cloud_name + '.conf'
        if os.path.isfile(cloud_config):
            return True
        else:
            return False

    # Check if Marvin definition exists
    def marvin_exists(self, marvin_config):
        if os.path.isfile(marvin_config):
            return True
        else:
            return False

    # Overview of what runs and what not
    def print_state(self):
        print "Overview of current VMs:"
        self.get_active_hosts()
        self.get_inactive_hosts()

    # List active Hosts
    def get_active_hosts(self):
        active_hosts = self.conn.listDomainsID()
        for id in active_hosts:
          dom = self.conn.lookupByID(id)
          print "VM " + dom.name() + " is ON."

    # List inactive Hosts
    def get_inactive_hosts(self):
        for name in self.conn.listDefinedDomains():
          dom = self.conn.lookupByName(name)
          print "VM " + dom.name() + " is SHUTDOWN."
        print

    # Get MAC and IP from Qemu
    def get_ip_and_mac(self, hostname):
        net = self.conn.networkLookupByName('NAT')
        root = ET.fromstring(net.XMLDesc())
        dhcp = root.findall("./ip/dhcp/host")
        result = {}
        for d in dhcp:
            if d.get('name') == hostname:
                result['mac'] = d.get('mac')
                result['name'] = d.get('name')
                result['ip'] = d.get('ip')
        if len(result)==0:
            print "ERROR: host not defined in NAT DHCP config."
            return False
        return result

    # Get all VMs
    def get_all_vms(self):
        result = {}
        for vm in self.conn.listAllDomains():
            id = vm.ID()
            result[id] = {}
            result[id]['name'] = vm.name()
            result[id]['state'] = vm.state()
        return result

    # Check exists
    def check_exists(self,name):
        try:
            dom = self.conn.lookupByName(name)
            return True
        except libvirt.libvirtError, e:
            sys.stdout.write("\033[F")
            sys.stdout.write("\033[2K")
            return False

    # Copy the qcow2 image we will use for our VM
    def copy_image(self, template, vm_name):
        try:
            template_image = self.config_data['template_dir'] + template + ".qcow2"
            new_image = self.config_data['image_dir'] + vm_name + ".img"
            shutil.copy2(template_image, new_image)
            return True
        except:
            return False

    # Read hardware xml
    def get_hardware_xml(self, hardware):
       xml = self.config_data['base_dir'] + "/" + self.config_data['hardware_dir'] + "/" + hardware + ".xml"
       return xml

    # Generate the XML for the new VM
    def generate_xml(self, role_name, vm_name):
        role_dict = self.get_role(role_name)
        xml = self.get_hardware_xml(role_dict['hardware'])
        with open(xml) as f:
            tmpl = Template(f.read())
        templatevars = self.get_role(role_name).copy()
        templatevars.update(self.get_offering(role_dict['offering']))
        templatevars['name'] = vm_name
        templatevars['format'] = 'qcow2'
        templatevars['disk_dev'] = role_dict['disk_dev']
        templatevars['disk_bus'] = role_dict['disk_bus']
        templatevars['net_model'] = role_dict['net_model']
        try:
            templatevars['mac'] = self.get_ip_and_mac(vm_name)['mac']
        except:
            return False
        return tmpl.render(templatevars)

    # Make the VM known to Qemu
    def define_vm(self, role_name, vm_name):
        try:
            xml = self.generate_xml(role_name, vm_name)
            domain = self.conn.defineXML(xml)
            return domain
        except:
            return False

    # Execute actions before starting the VM, like adding a first-boot script
    def firstboot_action(self, role_name, vm_name):
        role_dict = self.get_role(role_name)
        try:
            command = "virt-customize -d " + vm_name + " --firstboot " + self.config_data['base_dir'] + "/" + self.config_data['firstboot_dir'] + role_dict['firstboot']
            if len(role_dict['firstboot']) > 0:
                print "Note: " + vm_name + ": Running pre_boot script: " + command
                return_code = subprocess.call(command, shell=True)
            else:
                return_code = 0
                print "WARNING: " + vm_name  + ": No firstboot script defined."
        except:
            print "ERROR: " + vm_name  + ": Firstboot script failed."
            return False
        return return_code

    # Start the VM
    def start_vm(self, vm_name):
        dom = self.get_domain(vm_name)
        try:
            dom.create()
            return True
        except:
            return False

    # Exectute actions after starting the VM, like a ping check
    def postboot_action(self, role_name, vm_name):
        role_dict = self.get_role(role_name)
        try:
            command = self.config_data['base_dir'] + "/" + self.config_data['postboot_dir'] + role_dict['postboot'] + " " + vm_name
            if len(role_dict['postboot']) > 0:
                print "Note: " + vm_name + ": Running postboot script: " + command
                return_code = subprocess.call(command, shell=True)
            else:
                return_code = 0
                print "WARNING: " + vm_name  + ": No postboot script defined."
        except:
            print "ERROR: " + vm_name  + ": Postboot script failed."
            return False
        return return_code

    # Exectute actions before/after deploying cloud roles
    def cloud_deploy_action(self, cloud_name, cloud_dict, phase, extra_arguments = None):
        action = phase + '_deploy'
        script_for_action = cloud_dict[action]
        if self.is_defined(script_for_action):
            try:
                command = self.config_data['base_dir'] + "/" + self.config_data[action + '_dir'] + script_for_action
                if extra_arguments is not None:
                    command += " " + (" ".join(extra_arguments))
                print "Note: " + cloud_name + ": Running " + action + " script: " + command
                return_code = subprocess.call(command, shell=True)
            except:
                print "ERROR: " + cloud_name  + ": " + action + " script failed."
                return False
        else:
            return_code = 0
            print "WARNING: " + cloud_name  + ": No " + action + " script defined."
        return return_code

    def is_defined(self, string):
        return bool(string and string.strip())

    # Exectute actions before deploying cloud roles
    def pre_deploy_action(self, cloud_name, cloud_data):
        self.cloud_deploy_action(cloud_name, cloud_data, 'pre')

    # Exectute actions before deploying cloud roles
    def post_deploy_action(self, cloud_name, cloud_data, vm_names):
        self.cloud_deploy_action(cloud_name, cloud_data, 'post', vm_names)

    # Get domain object from libvirt
    def get_domain(self, vm_name):
        return self.conn.lookupByName(vm_name)

    # Deploy a certain hostname
    def deploy_host(self, hostname):
        role = hostname[:-1]
        digit = hostname[-1:]
        print "Note: Found role '" + role + "' and digit '" + digit + "'"
        return self.deploy_role(role, digit)

    # Delete
    def delete_host(self, hostname):
        print "Deleting vm '" + hostname + "'.."
        try:
            # Destroy
            command = "virsh destroy " + hostname
            return_code = subprocess.call(command, shell=True)
            # Undefine
            command = "virsh undefine " + hostname
            return_code = subprocess.call(command, shell=True)
            # Delete
            command = "sudo rm /data/images/" + hostname + ".img"
            return_code = subprocess.call(command, shell=True)
        except:
            return False
        return True

    # Delete host role wrapper
    def delete_host_role_wrapper(self, role_name, digit):
        role_dict = self.get_role(role_name)
        d.delete_host(role_dict['vm_prefix'] + digit)

    # Deploy a VM with a given role
    def deploy_role(self, role_name, digit=''):
        role_name = role_name.strip()
        if role_name == '':
            print "Error: no role_name supplied"
            return False
        # Clean is specific hostname
        if digit != '' and self.FORCE == 1:
            self.delete_host(role_name + digit)
        # Generate name
        vm_name = self.generate_vm_name(role_name, digit)
        if vm_name is False:
            print "Note: Exiting while deploying '" + role_name + digit + "'"
            return False
        try:
            # Get role
            role_data = self.get_role(role_name)
            # Copy template to image
            self.copy_image(role_data['image'], vm_name)
            # Define the vm in Qemu
            self.define_vm(role_name, vm_name)
            # Exec firstboot action
            self.firstboot_action(role_name, vm_name)
            # Start domain
            self.start_vm(vm_name)
            # Exec postboot action
            self.postboot_action(role_name, vm_name)
        except:
            return None
        return vm_name

    # Generate a name for the VM
    def generate_vm_name(self, role_name, digit=''):
        role_dict = self.get_role(role_name)
        if role_dict is False:
            print "Error: role '" + role_name + "' unknown."
            return False
        if digit == '':
            for n in range (1, 9):
                name = role_dict['vm_prefix'] + str(n)
                if not self.check_exists(name):
                    print "Note: VM name " + name + " is available"
                    return name
                print "Note: VM name " + name + " is already in use"
        else:
            name = role_dict['vm_prefix'] + str(digit)
            if self.check_exists(name):
                print "Note: VM name " + name + " is already in use"
            else:
                print "Note: VM name " + name + " is requested and available"
                return name
        print "ERROR: No available names for '" + role_dict['vm_prefix'] + "'"
        return False

    # Deploy a set of roles
    def deploy_cloud(self, cloud_name):
        try:
            # Get cloud
            cloud_data = self.get_cloud(cloud_name)
            # Exec pre_deploy action
            self.pre_deploy_action(cloud_name, cloud_data)
            # Deploy Cloud Roles
            vm_names = self.deploy_cloud_roles(cloud_data['deploy_roles'].split(','))
            sort_function = self.sort_function_for_cloud(cloud_name)
            # Exec post_deploy action
            self.post_deploy_action(cloud_name, cloud_data, sorted(vm_names, key=sort_function))
        except:
            return False
        return True

    def sort_function_for_cloud(self, cloud_name):
        if cloud_name == "nsx_cluster":
            return self.sort_nsx_vm_name
        else:
            # id function returns it's argument: id(1) = 1
            return id

    # Helper for sorting NSX cluster VMs in the way post_deploy script expects them
    def sort_nsx_vm_name(self, vm_name):
        if 'mgr' in vm_name:
            return 1
        elif 'con':
            return 2
        elif 'svc':
            return 3
        else:
            return 4

    def deploy_cloud_roles(self, roles):
        pool = ThreadPool(4)
        results = pool.map(self.deploy_role, roles)
        pool.close()
        pool.join()
        return results

    # Load the json file
    def load_marvin_json(self):
        try:
            print "Note: Processing Marvin config '" + self.marvin_config + "'"
            config_lines = []
            with open(self.marvin_config) as file_pointer:
                for line in file_pointer:
                    ws = line.strip()
                    if not ws.startswith("#"):
                        config_lines.append(ws)
            self.marvin_data = json.loads("\n".join(config_lines))
            return True
        except:
            print "Error: loading Marvin failed"
            return False

    # Get Marvin json
    def get_marvin_json(self):
        if not self.marvin_data:
            self.load_marvin_json()
        return self.marvin_data

    # Hypervisor type
    def get_hypervisor_type(self, zone=0, pod=0, cluster=0):
        if not self.marvin_data:
            self.load_marvin_json()
        return self.marvin_data['zones'][zone]['pods'][pod]['clusters'][cluster]['hypervisor'].lower()

    # Get hypervisors from Marvin
    def get_hosts(self, zone=0, pod=0, cluster=0):
        hosts = []
        if not self.marvin_data:
            self.load_marvin_json()
        for h in self.marvin_data['zones'][zone]['pods'][pod]['clusters'][cluster]['hosts']:
            url_split = h['url'].split('/')
            hosts.append(url_split[2].split('.')[0])
        return hosts

    # Deploy Marvin infra
    def deploy_marvin(self):
        if not self.get_marvin_json():
            return False
        print "Note: Found hypervisor type '" + self.get_hypervisor_type() + "'"
        hosts = self.get_hosts()
        pool = ThreadPool(4)
        results = pool.map(self.deploy_host, hosts)
        pool.close()
        pool.join()
        return True

    # Delete Marvin infra
    def delete_marvin(self):
        if not self.get_marvin_json():
            return False
        print "Note: Found hypervisor type '" + self.get_hypervisor_type() + "'"
        hosts = self.get_hosts()
        pool = ThreadPool(4)
        results = pool.map(self.delete_host, hosts)
        pool.close()
        pool.join()
        return True

# Init our class
d = kvm_local_deploy(DEBUG, DRYRUN, FORCE, deploy_marvin)

# Display status
if display_state == True:
    d.print_state()

# Deploy a cloud
if len(deploy_cloud) > 0:
    print "Note: You want to deploy a cloud based on config file '" + deploy_cloud + "'.."
    if not d.cloud_exists(deploy_cloud):
        print "Error: the cloud does not exist."
        sys.exit(1)
    # Deploy it
    if not d.deploy_cloud(deploy_cloud):
        sys.exit(1)
    sys.exit(0)

# Deploy a Marvin data center
if len(deploy_marvin) > 0:
    # Delete
    if delete == 1:
       print "Note: Deleting"
       d.delete_marvin()
       sys.exit(0)

    print "Note: You want to deploy a cloud based on Marvin config file '" + deploy_marvin + "'.."
    if not d.marvin_exists(deploy_marvin):
        print "Error: the Marvin config file '" + deploy_marvin  + "' does not exist."
        sys.exit(1)
    # Deploy it
    if not d.deploy_marvin():
        sys.exit(1)
    sys.exit(0)

# Deploy a role
if len(deploy_role) > 0:
    # Delete
    if delete == 1 and digit != '':
        print "Note: Deleting"
        d.delete_host_role_wrapper(deploy_role, digit)
        sys.exit(0)

    # Create
    print "Note: You want to deploy a VM with role '" + deploy_role + "'.."
    if not d.role_exists(deploy_role):
        print "Error: the role does not exist."
        sys.exit(1)
    if d.deploy_role(deploy_role, digit) is None:
        sys.exit(1)
    sys.exit(0)

# Deploy a vm
if len(deploy_vm) > 0:
    # Delete
    if delete == 1:
        print "Note: Deleting"
        d.delete_host(deploy_vm + digit)
        sys.exit(0)

    # Create
    print "Note: You want to deploy a VM with name '" + deploy_vm + "'.."
    if d.deploy_host(deploy_vm + digit) is None:
        sys.exit(1)
    sys.exit(0)
