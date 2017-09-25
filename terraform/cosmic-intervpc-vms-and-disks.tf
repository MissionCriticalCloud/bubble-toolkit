variable "cszone" {
    default = "MCCT-SHARED-1"
}

variable "requiredzones" {
    default  = "Bubble"
}

variable "vpccidrs" {
    default = "10.1,10.2,10.3"
}

variable "vpcoffering" {
    type = "map"
    default = {
       Bubble = "Default VPC offering",
    }
}

variable "privatenw_cidr" {
    default = "10.4.0.0/24"
}

variable "default_allow_acl_id" {
    default = "ad692983-6d7b-11e7-8f09-5254001daa61"
}

variable "networkoffering" {
    default = "DefaultIsolatedNetworkOfferingForVpcNetworks"
}

variable "privatenetworkoffering" {
    default = "DefaultPrivateGatewayNetworkOffering"
}

variable "serviceoffering" {
    default = {
        Bubble = "Small Instance"
    }
}

variable "template" {
    default = "tiny linux kvm"
}

variable "disk_offering" {
    default = "Small"
}

variable "requiredtiers" {
    default = "APP"
}

provider "cosmic" {
    api_url    = "http://192.168.22.61:8080/client/api/"
    api_key    = "add_key"
    secret_key = "add_secret"
}

# Creating the VPC's
resource "cosmic_vpc" "vpcs" {
    count           = "${length(split(",",var.requiredzones))}"
    name            = "oattest-intervpc-vpc-${count.index + 1}"
    cidr            = "${element(split(",",var.vpccidrs),count.index)}.0.0/20"
    network_domain  = "intervpc.local"
    vpc_offering    = "${lookup(var.vpcoffering,element(split(",",var.requiredzones),count.index))}"
    zone            = "${var.cszone}"
}

resource "cosmic_network_acl" "acls" {
    count    = "${length(split(",",var.requiredzones))}"
    name     = "intervpc-acl-${count.index + 1}"
    vpc_id   = "${element(cosmic_vpc.vpcs.*.id,format("%d", count.index % length(split(",",var.requiredzones))))}"
}

resource "cosmic_network_acl_rule" "extravpc_rules" {
    count    = "${length(split(",",var.requiredzones))}"
    acl_id   = "${element(cosmic_network_acl.acls.*.id,count.index)}"
    rule {
        cidr_list = ["10.0.0.0/8","192.168.0.0/16"] 
        action = "allow"
        protocol = "icmp"
        icmp_code = "-1"
        icmp_type = "-1"
        traffic_type = "ingress"
    }
    rule {
        cidr_list = ["10.0.0.0/8","192.168.0.0/16"] 
        action = "allow"
        protocol = "tcp"
        ports = ["22"]
        traffic_type = "ingress"
    }
    rule {
        cidr_list = ["10.0.0.0/8","192.168.0.0/16","0.0.0.0/0"] 
        action = "allow"
        protocol = "all"
        traffic_type = "egress"
    }
}

resource "cosmic_network" "networks" {
    count               = "${length(split(",",var.requiredzones)) * length(split(",",var.requiredtiers))}"
    name                = "intervpc-net-${count.index + 1}"
    cidr                = "${element(split(",",var.vpccidrs),count.index % length(split(",",var.requiredzones)))}.1.0/24"
    gateway             = "${element(split(",",var.vpccidrs),count.index % length(split(",",var.requiredzones)))}.1.1"
    network_offering    = "${var.networkoffering}"
    zone                = "${var.cszone}"
    vpc_id              = "${element(cosmic_vpc.vpcs.*.id,format("%d", count.index % length(split(",",var.requiredzones))))}"
    acl_id              = "${element(cosmic_network_acl.acls.*.id,format("%d", count.index % length(split(",",var.requiredzones))))}"
}


resource "cosmic_network" "privatenetwork" {
    depends_on          = ["cosmic_network.networks"]
    name                = "oattest-intervpc-net-private-network"
    cidr                = "${var.privatenw_cidr}"
    network_offering    = "${var.privatenetworkoffering}"
    zone                = "${var.cszone}"
}

resource "cosmic_private_gateway" "private_gws" {
    count           = "${length(split(",",var.requiredzones))}"
    ip_address      = "${cidrhost(var.privatenw_cidr, count.index + 1)}"
    network_id      = "${cosmic_network.privatenetwork.id}"
    acl_id          = "${var.default_allow_acl_id}"
    vpc_id          = "${element(cosmic_vpc.vpcs.*.id, count.index)}"
}

resource "cosmic_static_route" "routes" {
    count           = "${length(split(",",var.requiredzones)) * (length(split(",",var.requiredzones)) - 1)}"
    cidr            = "${element(cosmic_vpc.vpcs.*.cidr, (format("%d", count.index / (length(split(",",var.requiredzones)) - 1))) + (count.index % (length(split(",",var.requiredzones)) - 1)) + 1)}"
    nexthop         = "${element(cosmic_private_gateway.private_gws.*.ip_address, (format("%d", count.index / (length(split(",",var.requiredzones)) - 1))) + (count.index % (length(split(",",var.requiredzones)) - 1)) + 1)}"
    vpc_id          = "${element(cosmic_vpc.vpcs.*.id, format("%d", count.index / (length(split(",",var.requiredzones)) - 1)))}"
}

resource "cosmic_instance" "servers" {
    count            = "${length(split(",",var.requiredzones)) * length(split(",",var.requiredtiers))}"
    expunge          = true
    name             = "oattest-intervpc-vm-${count.index + 1}"
    service_offering = "${lookup(var.serviceoffering,element(split(",",var.requiredzones),count.index))}"
    template         = "${var.template}"
    zone             = "${var.cszone}"
    network_id       = "${element(cosmic_network.networks.*.id,count.index)}"
    ip_address       = "${element(split(",",var.vpccidrs),count.index % length(split(",",var.requiredzones)))}.1.10"
}

resource "cosmic_disk" "servers_disk" {
    count            = "17"
    name             = "${element(cosmic_instance.servers.*.name, count.index)}-fastq${count.index}"
    attach           = "true"
    disk_offering    = "${var.disk_offering}"
    virtual_machine_id  = "${element(cosmic_instance.servers.*.id, count.index)}"
    zone             = "${var.cszone}"
}

resource "cosmic_ipaddress" "publicips" {
    count           = "${length(split(",",var.requiredzones))}"
    vpc_id          = "${element(cosmic_vpc.vpcs.*.id ,count.index)}"
}

resource "cosmic_port_forward" "linux_bastions" {
    count                  = "${length(split(",",var.requiredzones)) * length(split(",",var.requiredtiers))}"
    depends_on             = ["cosmic_instance.servers"]
    ip_address_id          = "${element(cosmic_ipaddress.publicips.*.id, count.index)}"
    forward {
        protocol           = "tcp"
        private_port       = 22
        public_port        = 22
        virtual_machine_id = "${element(cosmic_instance.servers.*.id, count.index)}"
        vm_guest_ip        = "${element(cosmic_instance.servers.*.ip_address, count.index)}"
    }
}

# Public IP's outputs check order of required zones.
output "ipaddress_publicips" {
    value = "${join(",",cosmic_ipaddress.publicips.*.ip_address)}"
}
