#!/bin/bash

BASE=/data/git/cs1
CLOUDSTACK=${BASE}/cloudstack
TESTDIR=/data/shared/marvin
MYDIR=$(pwd -P)
DBSVR=cs1
export SCRIPT=${CLOUDSTACK}/scripts/storage/secondary
export INSTALL_VM=cloud-install-sys-tmplt
export XENTEMPLATE=${MYDIR}/systemvm/systemvm64template-systemvm-persistent-config-4.6.0.88-xen.vhd.bz2
export KVMTEMPLATE=${MYDIR}/systemvm/systemvm64template-master-4.6.0-kvm.qcow2.bz2

MAVEN_OPTS='-Xmx1024m -XX:MaxPermSize=500m -Xdebug -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=n'
MAVEN_OPTS='-Xmx1024m -XX:MaxPermSize=500m'
export SECSTOREBASE=/data/storage/secondary
PROFILE=xen1

updateAgent() {
	cd $CLOUDSTACK
	echo Packaging rpms and installing on hypervisor
	VERSION=`mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version | grep --color=none '^[0-9]\.'`
	echo $VERSION
	cd packaging
	sh ./package.sh -p oss -d centos7
	FILES="cloudstack-agent-${VERSION}.el7.centos.x86_64.rpm cloudstack-common-${VERSION}.el7.centos.x86_64.rpm"

	for i in $FILES
	do
		scp -q ${CLOUDSTACK}/dist/rpmbuild/RPMS/x86_64/${i} ${HYPERVISOR}:
	done
	ssh -t ${HYPERVISOR} sudo rpm --force -U $FILES
	ssh -t ${HYPERVISOR} sudo /etc/init.d/cloudstack-agent restart
	echo Done
}

installSystemvm() {
	if [ ! -d ${SCRIPT} ]
	then
		echo "Could not locate ${SCRIPT}"
		exit 2
	fi
	sudo sh ${SCRIPT}/${INSTALL_VM} -m ${SECSTORE} -f ${SYSTEMTEMPLATE} -h $HYPERVISOR_TYPE -o 127.0.0.1 \
                -r cloud -d cloud -t $TEMPLATE -e $TEMPTYPE -F
}

prepareDatabase() {
	cd ${MYDIR}
	cp ${MYDIR}/developer-prefill.sql ${CLOUDSTACK}/developer/developer-prefill.sql.override
	cp ${MYDIR}/db.properties.override ${CLOUDSTACK}/utils/conf

	mysql -h ${DBSVR} -u cloud --password=cloud -e 'drop database cloud;'
	cd ${CLOUDSTACK}
	mvn -P developer ${NOREDIST} -Ddeploydb -pl developer 
}

buildCloudstack() {
	cd ${CLOUDSTACK}
	mvn -T 2C -Psystemvm ${NOREDIST} -P developer,systemvm clean install
}

cleanKvm() {
	echo Cleaning KVM Hypervisor
	cd ${MYDIR}
	scp cleanKvm.sh ${HYPERVISOR}:
	ssh -t ${HYPERVISOR} sudo sh ./cleanKvm.sh
}

cleanXen() {
	cd ${MYDIR}
	echo Cleaning Xen Hypervisor
	python xapi_cleanup_xenservers.py http://${HYPERVISOR} root password
}


cleanHypervisor() {
	case $HYPERVISOR_TYPE in
		kvm)
			cleanKvm
			;;
		xenserver)
			cleanXen
			;;
		*)
			echo Dunno
			;;
	esac
}

bailout() {
	echo $1
	exit $2
}

runCloudstack() {
	cd ${CLOUDSTACK}
	CSPID=$(ps -ef | grep java|grep systemvm| awk '{print $2;}')
	if [ "$CSPID" != '' ]
        then
             kill ${CSPID}
        fi
	rm jetty-console.out
	rm vmops.log
	mvn -P systemvm ${NOREDIST} -pl :cloud-client-ui jetty:run > jetty-console.out 2>&1 &
	COUNTER=0
	while [ "$COUNTER" -lt 34 ] ; do
	    if grep -q 'Management server node 127.0.0.1 is up' jetty-console.out ; then
		break
	    fi
	    sleep 5
	    COUNTER=$(($COUNTER+1))
	done
	if grep -q 'Management server node 127.0.0.1 is up' jetty-console.out ; then
	   echo Started OK
	else
           bailout "Cloudstack failed to start" 2
	fi
}

runTest() {
	TEST=$1
	HW=$2
	echo Running test $1 hardware=$HW on $ZONE from $TESTDIR
	cd ${MYDIR}
 	nosetests --with-marvin --marvin-config=${TESTDIR}/${SCENARIO}  \
	-w ${CLOUDSTACK}/test/integration/$TESTS/ \
	--with-xunit --xunit-file=/tmp/bvt_provision_cases.xml \
	--zone=${ZONE} --hypervisor=$HYPERVISOR_TYPE \
	--exclude-dir=${CLOUDSTACK}/test/integration/smoke/misc \
	-s -a tags=advanced,required_hardware=${HW} \
        ${TEST}
}

runTestHW() {
	runTest $1 true
}

runTestNHW() {
	runTest $1 false
}

runComponentTests() {
	export TESTS=component
	#runTestNHW test_accounts.py

	# Needs cluster
	#runTestHW test_vpc_routers.py
	runTestHW test_vpc_network_pfrules.py
}

runSmokeTests() {
	export TESTS=smoke
	# Hardware enabled
	runTestHW test_deploy_vm_iso.py
	runTestHW test_deploy_vm_root_resize.py
	runTestHW test_deploy_vm_with_userdata.py
	runTestHW test_iso.py
	runTestHW test_loadbalance.py
	runTestHW test_network_acl.py
	runTestHW test_routers.py
	runTestHW test_service_offerings.py
	runTestHW test_snapshots.py
	runTestHW test_ssvm.py
	runTestHW test_templates.py
	runTestHW test_vm_life_cycle.py
	runTestHW test_vm_snapshots.py
	runTestHW test_volumes.py
	# Hardware Disabled
	runTestNHW test_global_settings.py
	runTestNHW test_multipleips_per_nic.py
	runTestNHW test_guest_vlan_range.py
	runTestNHW test_hosts.py
	runTestNHW test_disk_offerings.py
	runTestNHW test_deploy_vms_with_varied_deploymentplanners.py
	runTestNHW test_nic_adapter_type.py
	runTestNHW test_non_contigiousvlan.py
	runTestNHW test_over_provisioning.py
	runTestNHW test_privategw_acl.py
	runTestNHW test_public_ip_range.py
	runTestNHW test_pvlan.py
	runTestNHW test_reset_vm_on_reboot.py
	runTestNHW test_resource_detail.py
	runTestNHW test_secondary_storage.py
	runTestNHW test_usage_events.py
	runTestNHW test_vpc_vpn.py

	# Fails
	##runTestHW test_internal_lb.py
	##runTestHW test_network.py
	##runTestHW test_nic.py
	##runTestHW test_primary_storage.py
	##runTestHW test_regions.py
	##runTestNHW test_portable_publicip.py

	# Scaling is disabled
	##runTest test_scale_vm.py
}

deployCloud() {
	echo Deploying cloud
	cd ${MYDIR}
 	nosetests --with-marvin --marvin-config=${TESTDIR}/${SCENARIO} \
	--zone=$ZONE --hypervisor=$HYPERVISOR_TYPE \
	-a tags=advanced,required_hardware=true \
	--deploy
}

while getopts "vbidcrtqmp:u" opt; do
  case $opt in
    b)
      BUILD='y'
      ;;
    i)
      INSTALLVM='y'
      ;;
    d)
      DEPLOYDB='y'
      ;;
    c)
      CLEANXEN='y'
      ;;
    r)
      RUNCLOUDSTACK='y'
      ;;
    t)
      RUNTESTS='y'
      ;;
    m)
      DEPLOYCLOUD='y'
      ;;
    p)
      PROFILE=$OPTARG
      ;;
    u)
      UPDATEAGENT="y"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

if [ -n "$PROFILE" ]
then
	SYS=$(echo $PROFILE | cut -c1-3)
	NUM=$(echo $PROFILE | cut -c4-4)
	if [ "$NUM" -eq "$NUM" ] 2> /dev/null
        then
	    echo Profile is $PROFILE
 	else
            echo Invalid profile
            bailout
        fi
	#ZONE=$(echo MCCT-${SYS}-${NUM} | tr '[:lower:]' '[:upper:]')
	ZONE=MCCT-SHARED-${NUM}
	SECSTORE=/data/storage/secondary/${ZONE}
	case "$SYS" in
		XEN|xen)
			HYPERVISOR_TYPE=xenserver
			SYSTEMTEMPLATE=$XENTEMPLATE
			TEMPLATE=1
			TEMPTYPE=vhd
			;;
		KVM|kvm)
			HYPERVISOR_TYPE=kvm
			SYSTEMTEMPLATE=$KVMTEMPLATE
			TEMPLATE=3
			TEMPTYPE=qcow2
			;;
		*)
			echo "Unsupported hypervisor"
			bailout
		;;
	esac
	HYPERVISOR=$(echo ${SYS}${NUM} | tr '[:upper:]' '[:lower:]')
	SCENARIO=$(echo mct-zone1-${SYS}${NUM}.cfg | tr '[:upper:]' '[:lower:]')
	echo Zone $ZONE
	echo Hypervisor Type $HYPERVISOR_TYPE
	echo Hypervisor $HYPERVISOR
	echo Scenario $SCENARIO
fi

if [ -n "$UPDATEAGENT" ]
then
	if [ "$HYPERVISOR_TYPE" == "kvm" ]
	then
		updateAgent
	fi
fi
if [ -n "$BUILD" ]
then
	buildCloudstack
fi
if [ -n "$INSTALLVM" ]
then
	installSystemvm
fi
if [ -n "$DEPLOYDB" ]
then
	prepareDatabase
fi
if [ -n "$CLEANXEN" ]
then
	cleanHypervisor
fi
if [ -n "$RUNCLOUDSTACK" ]
then
	runCloudstack
fi
if [ -n "$DEPLOYCLOUD" ]
then
 	deployCloud	
fi
if [ -n "$RUNTESTS" ]
then
	runSmokeTests
	runComponentTests
fi


