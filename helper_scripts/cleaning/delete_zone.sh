#!/bin/bash

# Delete a zone, taken from Apache CloudStack wiki and altered to make it work with recent versions.

#set -x

usage() {
  printf "\nUsage: [-z]\n -z - zone id from db (integer) \n\nExample: zone_delete.sh -z1\n\n"
}

zone=

while getopts "z:" OPTION
do
     case $OPTION in
	 z)
	     zone=$OPTARG
	     ;;
     esac
done

if  [ "$zone" == "" ]
then
    printf "\nPlease make sure this file has the proper credentials for connecting: ~/.my.cnf\n"
    printf "\nZone Id is required\n"
    usage
    exit 3
fi

query[0]="update cloud.networks set removed = now() where data_center_id"
query[1]="update cloud.image_store set removed = now() where data_center_id"
query[2]="update cloud.cluster set removed = now() where data_center_id"
query[3]="update cloud.volumes set removed = now() where data_center_id"
query[4]="delete from cloud.snapshots where data_center_id"
query[5]="delete from cloud.vlan where data_center_id"
query[6]="delete from cloud.op_dc_ip_address_alloc where data_center_id"
query[7]="delete from cloud.op_dc_link_local_ip_address_alloc where data_center_id"
query[8]="delete from cloud.dc_storage_network_ip_range where data_center_id"
query[9]="update cloud.host_pod_ref set removed = now() where data_center_id"
query[10]="delete from cloud.op_dc_vnet_alloc where data_center_id"
query[11]="update cloud.host set removed = now() where data_center_id"
query[12]="delete from cloud.user_ip_address where data_center_id"
query[13]="delete from cloud.user_statistics where data_center_id"
query[14]="update cloud.vm_instance set removed = now() where data_center_id"
query[15]="update cloud.template_zone_ref set removed = now() where zone_id"
query[16]="update cloud.account set default_zone_id = null where default_zone_id"
query[17]="delete from cloud.op_host_capacity where data_center_id"
query[18]="delete from cloud.alert where data_center_id"
query[19]="update cloud.storage_pool set removed = now() where data_center_id"
query[20]="delete from cloud.op_pod_vlan_alloc where data_center_id"
query[21]="delete from cloud.data_center_details where dc_id"
query[22]="update cloud.physical_network set removed = now() where data_center_id"
query[23]="update cloud.vpc_gateways set removed = now() where zone_id"
query[24]="delete from cloud.volume_host_ref where zone_id"
query[25]="delete from cloud.usage_event where zone_id"
query[26]="update cloud.vpc set removed = now() where zone_id"
query[27]="update cloud.data_center set removed = now() where id"
query[28]="update cloud.autoscale_vmprofiles set removed = now() where zone_id"
query[29]="update cloud.autoscale_vmgroups set removed = now() where zone_id"
query[30]="update cloud.volume_view set removed = now() where data_center_id"
query[31]="delete from cloud.ucs_manager where zone_id"
query[32]="delete from cloud.user_ipv6_address where data_center_id"
query[33]="update cloud.user_vm_view set removed = now() where data_center_id"
query[34]="update cloud.domain_router_view set removed = now() where data_center_id"
query[35]="update cloud.host_view set removed = now() where data_center_id"
query[36]="update cloud.storage_pool_view set removed = now() where data_center_id"
query[37]="update cloud.vm_reservation set removed = now() where data_center_id"
query[38]="delete from cloud.volume_store_ref where zone_id"
query[39]="delete from cloud.vmware_data_center_zone_map where zone_id"
query[40]="delete from cloud.legacy_zones where zone_id"
query[41]="delete from cloud.portable_ip_address where data_center_id"
query[42]="update cloud.template_view set removed = now() where data_center_id"
query[43]="update cloud.data_center_view set removed = now() where id"
query[44]="delete from cloud.external_stratosphere_ssp_tenants where zone_id"
query[45]="update cloud.image_store_view set removed = now() where data_center_id"
query[46]="delete from cloud.snapshots where data_center_id IN (select id from data_center WHERE name is NULL)"
query[47]="delete from cloud.snapshot_store_ref where snapshot_id NOT IN (select id from snapshots)"

zone_exits=(`mysql --defaults-file=~/.my.cnf --skip-column-names -U cloud -e "select id from data_center where id = $zone and removed is null"`)
if [ "${#zone_exits[@]}" == "0" ];then
	echo "Zone : $zone does not exist or is removed"
	exit 2
fi

echo "Removing template store ref entries for zone: $zone"
stores=(`mysql --defaults-file=~/.my.cnf --skip-column-names -U cloud -e "select id from cloud.image_store where data_center_id = $zone and removed is null"`)
for ((i=0;i<${#stores[*]};i++)) 
do
	echo "Executing: delete from template_store_ref where store_id = ${stores[i]}"
	`mysql -defaults-file=~/.my.cnf --skip-column-names cloud -e "delete from cloud.template_store_ref where store_id = ${stores[i]}"`
	if [ "$?" != 0 ];then
		echo "Error while removing template store ref entries: $zone"
		exit 2
	fi
done

echo "Removing Zone: $zone"
for ((i=0;i<${#query[*]};i++)) 
do
	echo "Executing: ${query[i]} = $zone"
	`mysql --defaults-file=~/.my.cnf --skip-column-names cloud -e "SET FOREIGN_KEY_CHECKS=0; ${query[i]} = $zone"`
	if [ "$?" != 0 ];then
		echo "Error while removing zone: $zone"
		exit 2
	fi
done

removed_zone=(`mysql --defaults-file=~/.my.cnf --skip-column-names -U cloud -e "select id from data_center where id = $zone and removed is null"`)
if [ "${#removed_zone[@]}" == "0" ];then
	echo "Successfully removed Zone: $zone"
else
	echo "Failed to remove Zone: $zone"
fi
