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
    global deploy_role
    deploy_role = ''
    global deploy_cloud
    deploy_cloud = ''
    global display_state 
    display_state = False

    # Usage message
    help = "Usage: ./" + os.path.basename(__file__) + ' [options]' + \
        '\n  --deploy-role -r \t\tDeploy VM with this role' + \
        '\n  --deploy-cloud -c \t\tDeploy group of VMs to build a cloud' + \
        '\n  --status -s \t\t\tDisplay status of your VMs' + \
        '\n  --debug\t\t\tEnable debug mode'

    try:
        opts, args = getopt.getopt(
            argv, "hr:c:s", [
                "deploy-role=", "deploy-cloud=", "status", "debug"])
    except getopt.GetoptError as e:
        print "Error: " + str(e)
        print help
        sys.exit(2)

    if len(opts) == 0:
        print help
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print help
            sys.exit()
        elif opt in ("-r", "--deploy-role"):
            deploy_role = arg
        elif opt in ("-c", "--deploy-cloud"):
            deploy_cloud = arg
        elif opt in ("-s", "--status"):
            display_state = True 
        elif opt in ("--debug"):
            DEBUG = 1

# Parse arguments
if __name__ == "__main__":
    handleArguments(sys.argv[1:])

# Deploy local KVM class
class kvm_local_deploy:
    
    # Init function
    def __init__(self, debug=0, dryrun=0, force=0):
        self.DEBUG = debug
        self.DRYRUN = dryrun
        self.FORCE = force
        self.configfile = os.getcwd() + '/config'
        try:
            self.conn = libvirt.open('qemu:///system')
        except Exception, e:
            print "ERROR: Could not connect to Qemu!"
            sys.exit(1)

        self.print_welcome()
        self.read_config_file(self.configfile)

    # Read our own config file for settings
    def read_config_file(self, configfile):
        config = ConfigParser.RawConfigParser()
        config.read(self.configfile)
        try:
            self.basedir = config.get('mct', 'basedir')
            self.templatedir = config.get('mct', 'templatedir')
            self.imagedir = config.get('mct', 'imagedir')
            self.offeringdir = self.basedir + config.get('mct', 'offeringdir')
            self.hardwaredir = self.basedir + config.get('mct', 'hardwaredir')
            self.firstbootdir = self.basedir + config.get('mct', 'firstbootdir')
            self.roledir = self.basedir + config.get('mct', 'roledir')
            self.clouddir = self.basedir + config.get('mct', 'clouddir')
        except:
            print "Error: Cannot read or parse mctDeploy config file '" + self.configfile + "'"
            print "Hint: Setup the local config file 'config', using 'config.sample' as a starting point. See documentation."
            sys.exit(1)

    # Read section from config file
    def get_config_section(self, configfile, section):
        config = ConfigParser.RawConfigParser()
        config.read(configfile)
        confdict = {}
        options = config.options(section)
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
    def get_offering(self, offeringname):
        offeringconfig = self.offeringdir + "/" + offeringname + '.conf'
        return self.get_config_section(offeringconfig, 'offering')

    # Get role details
    def get_role(self, role_name):
        if self.role_exists(role_name):
            role_config = self.roledir + "/" + role_name + '.conf'
            return self.get_config_section(role_config, 'role')
        else:
            return False

    # Check if role definition exists
    def role_exists(self, role_name):
        role_config = self.roledir + "/" + role_name + '.conf'
        if os.path.isfile(role_config):
            return True
        else:
            return False

    # Get cloud details
    def get_cloud(self, cloud_name):
        if self.cloud_exists(cloud_name):
            cloud_config = self.clouddir + "/" + cloud_name + '.conf'
            return self.get_config_section(cloud_config, 'cloud')
        else:
            return False

    # Check if cloud definition exists
    def cloud_exists(self, cloud_name):
        cloud_config = self.clouddir + "/" + cloud_name + '.conf'
        if os.path.isfile(cloud_config):
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
            sys.exit(1)
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
            template_image = self.templatedir + template + ".qcow2"
            new_image = self.imagedir + vm_name + ".img"
            shutil.copy2(template_image, new_image)
            return True
        except:
            return False

    # Read hardware xml
    def get_hardware_xml(self, hardware):
       xml = self.hardwaredir + "/" + hardware + ".xml"
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
        templatevars['mac']= self.get_ip_and_mac(vm_name)['mac']
        return tmpl.render(templatevars)

    # Make the VM known to Qemu
    def define_vm(self, role_name, vm_name):
        xml = self.generate_xml(role_name, vm_name)
        try:
            domain = self.conn.defineXML(xml)
            return domain  
        except:
            return False

    # Execute actions before starting the VM, like adding a first-boot script
    def pre_start_action(self, role_name, vm_name):
        role_dict = self.get_role(role_name)
        try:
            command = "virt-customize -d " + vm_name + " --firstboot " + role_dict['firstboot']
            if len(role_dict['firstboot']) > 0:
                print "Note: Running pre_boot script: " + command
                return_code = subprocess.call(command, shell=True)  
            else:
                return_code = 0 
                print "WARNING: No pre_start script defined."
        except:
            print "ERROR: pre_start script failed."
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
    def post_start_action(self, role_name, vm_name):
        role_dict = self.get_role(role_name)
        try:
            command = role_dict['post_start_script'] + " " + vm_name
            if len(role_dict['post_start_script']) > 0:
                print "Note: Running post_start script: " + command
                return_code = subprocess.call(command, shell=True)  
            else:
                return_code = 0 
                print "WARNING: No post_start script defined."
        except:
            print "ERROR: post_start script failed."
            return False
        return return_code

    # Get domain object from libvirt
    def get_domain(self, vm_name):
        return self.conn.lookupByName(vm_name)

    # Deploy a VM with a given role
    def deploy_role(self, role_name):
        # Generate name
        vm_name = self.generate_vm_name(role_name)
        if vm_name is False:
            sys.exit(1)
        # Get role
        role_data = self.get_role(role_name)
        # Copy template to image
        self.copy_image(role_data['image'], vm_name)
        # Define the vm in Qemu
        self.define_vm(role_name, vm_name)
        # Exec pre_start action
        self.pre_start_action(role_name, vm_name)
        # Start domain
        self.start_vm(vm_name)
        # Exec post_start action
        self.post_start_action(role_name, vm_name)

    # Generate a name for the VM
    def generate_vm_name(self, role_name):
        role_dict = self.get_role(role_name)
        print "Note: Need a VM with name " + role_dict['vm_prefix']
        for n in range (1, 10): 
            name = role_dict['vm_prefix'] + str(n)
            if not self.check_exists(name):
                print "Note: VM name " + name + " is available."
                return name
            print "Note: VM name " + name + " is already in use."
        print "ERROR: No available names for '" + role_dict['vm_prefix'] + "'"
        return False

    # Deploy a set of roles
    def deploy_cloud(self, cloud_name):
        # Read config file, for each role deploy_role
        cloud_data = self.get_cloud(cloud_name)
        roles = cloud_data['deploy_roles'].split(',')
        for r in roles:
            role = r.strip()
            print "Note: deploying role " + role
            self.deploy_role(role)

# Init our class
d = kvm_local_deploy(DEBUG, DRYRUN)

# Display status
if display_state == True:
    d.print_state()

# Deploy a cloud
if len(deploy_cloud) > 0:
    print "Note: You want to deploy a VM with cloud '" + deploy_cloud + "'.."
    if not d.cloud_exists(deploy_cloud):
        print "Error: the cloud does not exist."
        sys.exit(1)
    # Deploy it
    d.deploy_cloud(deploy_cloud)
    sys.exit(0)

# Deploy a role
if len(deploy_role) > 0:
    print "Note: You want to deploy a VM with role '" + deploy_role + "'.."
    if not d.role_exists(deploy_role):
        print "Error: the role does not exist."
        sys.exit(1)
    # Deploy it
    d.deploy_role(deploy_role)
    sys.exit(0)

