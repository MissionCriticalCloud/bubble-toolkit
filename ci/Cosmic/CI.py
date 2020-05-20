from __future__ import print_function

import glob
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time

import marvin.deployDataCenter
import marvin.marvinInit
import mysql.connector
import nose
import paramiko
import requests
import scp
from jsonpath_ng import parse
from cmds import CMDS as CMDS
from . import Base


class CIException(Exception):
    pass


class CI(Base.Base):
    """Initializes CI class with the given ``marvin_config`` file

    :param marvin_config: Path to marvin file
    :param debug: Output debug information
    """
    def __init__(self, marvin_config=None, debug=False):
        super(CI, self).__init__(marvin_config=marvin_config, debug=debug)
        self.workspace = '/data/git'
        self.setup_files = '/data/shared'
        self.templatepath = '/template/tmpl/1/3'
        self.templateuuid = 'f327eecc-be53-4d80-9d43-adaf45467abd'
        self.flywayversion = '6.1.3'
        self.flywaycli = ('https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/'
                          '{fwv}/flyway-commandline-{fwv}-linux-x64.tar.gz'.format(fwv=self.flywayversion))
        self.mariadbversion = '2.3.0'
        self.mariadbjar = ('https://beta-nexus.mcc.schubergphilis.com/service/local/artifact/maven/'
                           'redirect?r=central&g=org.mariadb.jdbc&a=mariadb-java-client&v=%s' % self.mariadbversion)

    def prepare(self, timeout=900, cloudstack_deploy_mode=""):
        """Prepare infrastructure for CI pipeline

        :param timeout: Timeout to wait for infra to be build
        :param cloudstack_deploy_mode: Deploy cloudstack infra
        """
        clusters = parse('zones[*].pods[*].clusters[*]').find(self.config)
        primarystorage = parse('zones[*].pods[*].clusters[*].primaryStorages[*]').find(self.config)
        secondarystorage = parse('zones[*].secondaryStorages[*]').find(self.config)

        for path in map(lambda x: x.value['url'].split(':')[2], primarystorage + secondarystorage):
            if not os.path.exists(path):
                os.makedirs(path)

        # There can only be one Hypervisor type KVM or Xen
        hypervisor = clusters[0].value['hypervisor'].lower()
        if hypervisor == 'kvm':
            print("==> Found hypervisor: %s; changing MTU to 1600" % hypervisor)
        elif hypervisor == 'xenserver':
            print("==> Found hypervisor: %s; changing MTU to 1500" % hypervisor)
        else:
            raise CIException("Hypervisor %s is unsupported, aborting" % hypervisor)

        for h in os.listdir('/sys/devices/virtual/net/virbr0/brif/'):
            for c in CMDS['MTU'][hypervisor]:
                subprocess.call(map(lambda x: x.format(dev=h), c.split(' ')))

        if cloudstack_deploy_mode:
            cloudstack_deploy_mode = "--cloudstack"
        if self.debug:
            print("==> Executing: ", CMDS['deploy'].format(marvin_config=self.marvin_config,
                                                           cloudstack_deploy_mode=cloudstack_deploy_mode))
        task = subprocess.Popen(map(lambda x: x.format(marvin_config=self.marvin_config,
                                                       cloudstack_deploy_mode=cloudstack_deploy_mode),
                                    CMDS['deploy'].split(' ')))
        retries = timeout
        # FIXME: In python3 subprocess.call has a timeout, this can then be removed
        while task.poll() is None and retries > 0:
            time.sleep(1)
            retries -= 1

        for cmd in CMDS['generic']:
            subprocess.call(cmd.split(' '))

    def cleanup(self, jsonpath=None, vm=None, name_path=None, result_filter=None, collect_logs=True):
        """Collect all data and cleanup VM's and images

        Example:
            ci = CI('/data/shared/marvin/marvin.json')
            ci.cleanup(config=config, jsonpath='zones[*].pods[*].clusters[*].hosts[*]', namepath='url',
                filter=lambda x: x.split('/')[::-1][0])

        :param jsonpath: JSONPath to filter out JSON
        :param vm: Name of the instance to remove
        :param name_path: Optional parameter to filter out json
        :param result_filter: Optional lambda to use on filtered result
        :param collect_logs: Collect logs and coverage files
        """
        for i in parse(jsonpath).find(self.config):
            properties = i.value
            username = properties.get('username', properties.get('user', 'root'))
            password = properties.get('password', properties.get('passwd', 'password'))

            if name_path:
                vm = parse(name_path).find(properties)[0].value
            if result_filter:
                vm = result_filter(vm)
            if collect_logs:
                print("==> Collecting Logs and Code Coverage Report from %s" % vm)
                # TODO: Copy logs and coverage reports from HV and SCP them
                # collect_files_from_vm ${csip} ${csuser} ${cspass} "/var/log/cosmic/management/*.log*" "cs${i}-management-logs/"
                if vm.startswith('cs'):
                    src = "/var/log/cosmic/management/*.log*"
                    dstdir = "%s-management-logs" % vm
                    hostname = properties['mgtSvrIp']
                else:
                    src = "/var/log/cosmic/agent/*.log*"
                    dstdir = "%s-agent-logs" % vm
                    hostname = vm
                if not os.path.exists(dstdir):
                    os.makedirs(dstdir)
                try:
                    self.collect_files_from_vm(hostname=hostname, username=username, password=password,
                                               src=src, dst="%s" % dstdir)
                except (scp.SCPException, paramiko.ssh_exception) as e:
                    print("ERROR: %s" % e.message)

            print("==> Destroying VM %s" % vm)
            # FIXME: Create library for this instead of a subprocess
            subprocess.call(['/data/shared/deploy/kvm_local_deploy.py', '-x', vm])

    def cleanup_storage(self):
        """Cleanup storage"""
        primarystorage = parse('zones[*].pods[*].clusters[*].primaryStorages[*]').find(self.config)
        secondarystorage = parse('zones[*].secondaryStorages[*]').find(self.config)
        for i in map(lambda x: x.value['url'].split(':')[2], primarystorage + secondarystorage):
            if os.path.exists(i):
                try:
                    shutil.rmtree("%s" % i)
                except OSError as e:
                    print("ERROR: %s" % e.message)

    def collect_files_from_vm(self, hostname='localhost', username=None, password=None, src=None, dst=None):
        """Collect logs and coverage files

        :param hostname: Hostname
        :param username: Username
        :param password: Password
        :param src: Source files
        :param dst: Destination directory
        """
        self._scp_get(hostname=hostname, username=username, password=password, srcfile=src, destfile=dst)

    def marvin_tests(self, tests=None):
        """Run Marvin tests

        :param tests: marvin tests to run
        """
        self.copy_marvin_config()

        # Run marvin tests
        old_path = os.getcwd()
        nose_args = ("nosetests --with-xunit --xunit-file={path}/nosetests.xml "
                     "--with-marvin --marvin-config={config} "
                     "-s -a tags=advanced {tests}".format(path=old_path,
                                                          config=self.marvin_config,
                                                          tests=" ".join(tests)))
        os.chdir("cosmic-core/test/integration")
        print("==> Running tests")
        if self.debug:
            print('==> Nose parameters: %s' % nose_args)
        ret = nose.run(argv=nose_args.split(" "))
        os.chdir(old_path)
        if not ret:
            sys.exit(1)
        sys.exit(0)

    def deploy_dc(self):
        """Deploy DC

        Use Marvin to deploy DC
        """
        print("==> Deploying Data Center")
        # TODO: Replace Marvin
        mrv = marvin.marvinInit.MarvinInit(self.marvin_config)
        mrv.init()
        dc = marvin.deployDataCenter.DeployDataCenters(mrv.getTestClient(), mrv.getParsedConfig())
        dc.deploy()

    def copy_marvin_config(self):
        """Copy Marvin file to current working directory"""
        print("==> Making local copy of Marvin Config file")
        marvin_filename = self.marvin_config.split('/')[-1]
        open(marvin_filename, "w").write(json.dumps(self.config, indent=4))

    def install_kvm_packages(self):
        """Prepare KVM hypervisor"""
        zones = parse('zones[*]').find(self.config)
        for zone in zones:
            hosts = parse('pods[*].clusters[*].hosts[*]').find(zone)
            for host in hosts:
                hostname = host.value['url'].split('/')[-1]
                connection = {'hostname': hostname, 'username': host.value['username'],
                              'password': host.value['password']}

                # Do pre-commands
                for cmd in CMDS['agent_install']['precommands']:
                    self._ssh(cmd=cmd, **connection)

                # SCP files
                for cmd in CMDS['agent_install']['scp']:
                    src_file = self.workspace + "/" + zone.value['name'] + "/cosmic/" + cmd[0]
                    self._scp_put(srcfile=src_file, destfile=cmd[1], **connection)
                    if self.debug:
                        print("==> scp %s %s:%s\n" % (src_file, hostname, cmd[1]))

                # Do post-commands
                for cmd in CMDS['agent_install']['postcommands']:
                    self._ssh(cmd=cmd, **connection)

    def deploy_cosmic_db(self):
        """Prepare Cosmic Database"""
        cmd = 'mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO \'root\'@\'%\' WITH GRANT OPTION; FLUSH PRIVILEGES;"'

        # TODO: At the moment there is only one DB server specified, so deployment only uses that DB server
        db_svr = self.config['dbSvr']['dbSvr']
        db_port = self.config['dbSvr']['port']
        db_user = self.config['dbSvr']['user']
        db_pass = self.config['dbSvr']['passwd']
        self.wait_for_port(hostname=db_svr, tcp_port=db_port)

        for mgtSvr in self.config['mgtSvr']:
            self._ssh(hostname=mgtSvr['mgtSvrIp'], username=mgtSvr['user'],
                      password=mgtSvr['passwd'], cmd=cmd)
            for query in open("%s/ci/setup_files/create-cloud-db.sql" % self.setup_files, "r").readlines():
                if query == '\n':
                    continue
                cloud_db = mysql.connector.connect(
                    host=self.config['dbSvr']['dbSvr'],
                    username="root"
                )
                cloud_cursor = cloud_db.cursor()
                cloud_cursor.execute(query)
                cloud_db.commit()
                cloud_db.close()

        for f in glob.glob('/tmp/flyway*'):
            os.unlink(f) if os.path.isfile(f) else shutil.rmtree(f)
        resp = requests.get(self.flywaycli)
        open('/tmp/flyway.tar.gz', 'w').write(resp.content)
        tar = tarfile.open('/tmp/flyway.tar.gz')
        tar.extractall(path='/tmp/')
        tar.close()

        for mgtSvr in self.config['mgtSvr']:
            subprocess.call(['/tmp/flyway-{fwv}/flyway'.format(fwv=self.flywayversion),
                             '-url=jdbc:mariadb://%s:%s/cloud' % (mgtSvr['mgtSvrIp'], db_port),
                             '-user=%s' % db_user,
                             '-password=%s' % db_pass,
                             '-encoding=UTF-8',
                             '-locations=filesystem:cosmic-core/cosmic-flyway/src',
                             '-baselineOnMigrate=true',
                             '-table=schema_version',
                             'migrate'])
            print('==> Cosmic DB deployed at %s' % mgtSvr['mgtSvrIp'])

        for f in glob.glob('/tmp/flyway*'):
            os.unlink(f) if os.path.isfile(f) else shutil.rmtree(f)

    def install_systemvm_templates(self, template=None):
        """Install SystemVM template

        :param template: File location of template file
        """
        tmpltsize = os.stat(template).st_size
        template_properties = (
            "filename={uuid}.qcow2\n"
            "description=SystemVM Template\n"
            "checksum=\n"
            "hvm=false\n"
            "size={tmpltsize}\n"
            "qcow2=true\n"
            "id=3\n"
            "public=true\n"
            "qcow2.filename={uuid}.qcow2\n"
            "uniquename=routing-3\n"
            "qcow2.virtualsize={tmpltsize}\n"
            "virtualsize={tmpltsize}\n"
            "qcow2.size={tmpltsize}\n".format(uuid=self.templateuuid, tmpltsize=tmpltsize)
        )

        secondarystorage = parse('zones[*].secondaryStorages[*]').find(self.config)

        for path in map(lambda x: x.value['url'].split(':')[2], secondarystorage):
            if not os.path.exists(path+self.templatepath):
                os.makedirs(path+self.templatepath)
            shutil.copyfile(template, "%s%s/%s.qcow2" % (path, self.templatepath, self.templateuuid))
            open("%s%s/template.properties" % (path, self.templatepath), 'w').write(template_properties)
        print('==> SystemVM templates installed')

    def configure_tomcat_to_load_jacoco_agent(self):
        """Deploy jacoco agent on management server"""
        open("/tmp/jacoco.conf", "w").write('JAVA_OPTS="$JAVA_OPTS -javaagent:/tmp/jacoco-agent.jar=destfile=/tmp/jacoco-it.exec"\n')
        zone = self.config['zones'][0]['name']
        for host in self.config['mgtSvr']:
            connection = {'hostname': host['mgtSvrIp'], 'username': host['user'], 'password': host['passwd']}
            src_file = self.workspace + "/" + zone + "/cosmic/target/jacoco-agent.jar"
            self._scp_put(srcfile=src_file, destfile="/tmp", **connection)
            self._scp_put(srcfile="/tmp/jacoco.conf", destfile="/etc/tomcat/conf.d/jacoco.conf", **connection)
        print("==> Tomcat configured")
        os.unlink("/tmp/jacoco.conf")

    def configure_agent_to_load_jacoco_agent(self):
        """Deploy jacoco agent on hypervisor"""
        zones = parse('zones[*]').find(self.config)
        for zone in zones:
            hosts = parse('pods[*].clusters[*].hosts[*]').find(zone)
            for host in hosts:
                hostname = host.value['url'].split('/')[-1]
                connection = {'hostname': hostname, 'username': host.value['username'],
                              'password': host.value['password']}
                cmd = r"sed -i -e 's|/bin/java -Xms|/bin/java -javaagent:/tmp/jacoco-agent.jar=destfile=/tmp/jacoco-it.exec -Xms|' /usr/lib/systemd/system/cosmic-agent.service"
                src_file = self.workspace + "/" + zone.value['name'] + "/cosmic/target/jacoco-agent.jar"
                self._scp_put(srcfile=src_file, destfile="/tmp", **connection)
                self._ssh(cmd=cmd, **connection)
                self._ssh(cmd="systemctl daemon-reload", **connection)
        print("==> Agent configured")

    def deploy_cosmic_war(self):
        """Deploy Cosmic WAR file"""
        resp = requests.get(self.mariadbjar)
        open('/tmp/mariadb-java-client-latest.jar', 'w').write(resp.content)

        zone = self.config['zones'][0]['name']

        template_vars = {
            'setup_files': "%s/ci/setup_files" % self.setup_files,
            'mariadbjar': "/tmp/mariadb-java-client-latest.jar",
            'war_file': "%s/%s/cosmic/cosmic-client/target/cloud-client-ui-*.war" % (self.workspace, zone)
        }

        for host in self.config['mgtSvr']:
            connection = {'hostname': host['mgtSvrIp'], 'username': host['user'], 'password': host['passwd']}

            # Do pre-commands
            for cmd in CMDS['war_deploy']['precommands']:
                self._ssh(cmd=cmd, **connection)

            # Do scp-commands
            for cmd in CMDS['war_deploy']['scp']:
                srcfile = cmd[0].format(**template_vars)
                self._scp_put(srcfile=srcfile, destfile=cmd[1], **connection)

            # Do post-commands
            for cmd in CMDS['war_deploy']['postcommands']:
                self._ssh(cmd=cmd, **connection)

        os.unlink("/tmp/mariadb-java-client-latest.jar")

    def collect_test_coverage_files(self):
        zone = self.config['zones'][0]['name']
        for host in self.config['mgtSvr']:
            connection = {'hostname': host['mgtSvrIp'], 'username': host['user'], 'password': host['passwd']}
            print("==> Stopping Tomcat on %s" % host['mgtSvrName'])
            self._ssh(cmd="systemctl stop tomcat", **connection)

            print("==> Collecting Integration Tests Coverage Data (Management Server) from %s" % host['mgtSvrName'])
            destfile = ("%s/%s/cosmic/target/coverage-reports/jacoco-it-%s.exec" %
                        (self.workspace, zone, host['mgtSvrName']))
            try:
                self._scp_get(srcfile="/tmp/jacoco-it.exec", destfile=destfile, **connection)
            except IOError as e:
                print("ERROR: %s" % (e.message or e.strerror))

        zones = parse('zones[*]').find(self.config)
        for zone in zones:
            hosts = parse('pods[*].clusters[*].hosts[*]').find(zone)
            for host in hosts:
                hostname = host.value['url'].split('/')[-1]
                connection = {'hostname': hostname, 'username': host.value['username'],
                              'password': host.value['password']}
                print("==> Stopping Cosmic KVM Agent on host %s" % hostname)
                self._ssh(cmd="systemctl stop cosmic-agent", **connection)

                destfile = ("%s/%s/cosmic/target/coverage-reports/jacoco-it-%s.exec" %
                            (self.workspace, zone.value['name'], hostname))
                print("==> Collecting Integration Tests Coverage Data (Agent) from %s" % hostname)
                try:
                    self._scp_get(srcfile="/tmp/jacoco-it.exec", destfile=destfile, **connection)
                except IOError as e:
                    print("ERROR: %s" % (e.message or e.strerror))
