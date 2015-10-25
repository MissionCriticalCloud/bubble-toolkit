import hudson.plugins.copyartifact.SpecificBuildSelector

// Job Parameters
def nodeExecutor     = executor
def parentJob        = parent_job
def parentJobBuild   = parent_job_build
def marvinConfigFile = marvin_config_file

def HOSTS             = ['kvm1', 'kvm2']
def SECONDARY_STORAGE = '/data/storage/secondary/MCCT-SHARED-1'

def DB_SCRIPTS = [
  'setup/db/db/',
  'setup/db/create-*.sql',
  'setup/db/templates*.sql',
  'developer/developer-prefill.sql'
]

def TEMPLATE_SCRIPTS = [
  'scripts/storage/secondary/'
]

def BUILD_ARTEFACTS = [
  'client/target/',
  'dist/rpmbuild/RPMS/x86_64/',
  'tools/marvin/dist/'
]

def MARVIN_SCRIPTS = [
  'test/integration/',
  'tools/travis/xunit-reader.py'
]

node(nodeExecutor) {
  def filesToCopy = BUILD_ARTEFACTS + DB_SCRIPTS + TEMPLATE_SCRIPTS + MARVIN_SCRIPTS
  copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy)

  sh  "cp /data/shared/marvin/${marvinConfigFile} ./"
  updateManagementServerIp(marvinConfigFile, 'cs1')

  parallel 'Deploy Management Server': {
    node(nodeExecutor) {
      def managementServerFiles = DB_SCRIPTS + TEMPLATE_SCRIPTS + ['client/target/']
      copyFilesFromParentJob(parentJob, parentJobBuild, managementServerFiles)
      deployMctCs()
      deployDb()
      installSystemVmTemplate('root@cs1', SECONDARY_STORAGE)
      deployWar()
    }
  }, 'Deploy Hosts': {
    deployHosts(marvinConfigFile)
    deployRpmsInParallel(HOSTS, nodeExecutor, parentJob, parentJobBuild, ['dist/rpmbuild/RPMS/x86_64/'])
  }, failFast: true

  archive marvinConfigFile
}

// ----------------
// Helper functions
// ----------------

// TODO: move to library
def copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy) {
  step ([$class: 'CopyArtifact',  projectName: parentJob,  selector: new SpecificBuildSelector(parentJobBuild), filter: filesToCopy.join(', ')]);
}

def deployWar() {
  ssh('root@cs1', 'mkdir -p /usr/share/tomcat/db')
  scp('setup/db/db/*', 'root@cs1:/usr/share/tomcat/db/')
  scp('client/target/cloud-client-ui-*.war', 'root@cs1:/usr/share/tomcat/webapps/client.war')
  ssh('root@cs1', 'service tomcat restart')
  echo '==> WAR deployed'
}

def deployMctCs() {
  deplyMctVm('-r', 'cloudstack-mgt-dev')
  echo '==> cs1 deployed'
}

def deployHosts(marvinConfig) {
  deplyMctVm('-m', marvinConfig)
  echo '==> kvm1 & kvm2 deployed'
}

def deplyMctVm(option, argument) {
  sh "/data/shared/deploy/kvm_local_deploy.py ${option} ${argument}"
}

def deployDb() {
  waitForMysqlToBeRunning('cs1')
  writeFile file: 'grant-remote-access.sql', text: 'GRANT ALL PRIVILEGES ON *.* TO \'root\'@\'%\' WITH GRANT OPTION; FLUSH PRIVILEGES;'
  scp('grant-remote-access.sql', 'root@cs1:./')
  ssh('root@cs1', 'mysql -u root < grant-remote-access.sql')
  mysqlScript('cs1', 'root',  '',      '', 'setup/db/create-database.sql')
  mysqlScript('cs1', 'root',  '',      '', 'setup/db/create-database-premium.sql')
  mysqlScript('cs1', 'root',  '',      '', 'setup/db/create-schema.sql')
  mysqlScript('cs1', 'root',  '',      '', 'setup/db/create-schema-premium.sql')
  mysqlScript('cs1', 'cloud', 'cloud', '', 'setup/db/templates.sql')
  mysqlScript('cs1', 'cloud', 'cloud', '', 'developer/developer-prefill.sql')
  def extraDbConfig = [
    'INSERT INTO cloud.configuration (instance, name, value) VALUE(\'DEFAULT\', \'host\', \'192.168.22.61\') ON DUPLICATE KEY UPDATE value = \'192.168.22.61\';',
    'INSERT INTO cloud.configuration (instance, name, value) VALUE(\'DEFAULT\', \'sdn.ovs.controller.default.label\', \'cloudbr0\') ON DUPLICATE KEY UPDATE value = \'cloudbr0\';',
    'UPDATE cloud.vm_template SET url=\'http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-xen.vhd.bz2\' where id=1;',
    'UPDATE cloud.vm_template SET url=\'http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2\' where id=3;',
    'UPDATE cloud.vm_template SET url=\'http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-kvm.qcow2.bz2\', guest_os_id=140, name=\'tiny linux kvm\', display_text=\'tiny linux kvm\', hvm=1 where id=4;',
    'UPDATE cloud.vm_template SET url=\'http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2\', guest_os_id=140, name=\'tiny linux xenserver\', display_text=\'tiny linux xenserver\', hvm=1 where id=2;',
    'UPDATE cloud.vm_template SET url=\'http://dl.openvm.eu/cloudstack/macchinina/x86_64/macchinina-xen.vhd.bz2\', guest_os_id=140, name=\'tiny linux xenserver\', display_text=\'tiny linux xenserver\', hvm=1 where id=5;',
    'UPDATE service_offering SET ha_enabled = 1;',
    'UPDATE vm_instance SET ha_enabled = 1;'
  ]
  writeFile file: 'extraDbConfig.sql', text: extraDbConfig.join('\n')
  mysqlScript('cs1', 'cloud', 'cloud', 'cloud', 'extraDbConfig.sql')

  writeFile file: 'dumpDb.sh', text: 'mysqldump -u root cloud > fresh-db-dump.sql'
  scp('dumpDb.sh', 'root@cs1:./')
  ssh('root@cs1', 'chmod +x dumpDb.sh; ./dumpDb.sh')
  archive 'fresh-db-dump.sql'
  sh 'rm -f grant-remote-access.sql extraDbConfig.sql fresh-db-dump.sql'

  echo '==> DB deployed'
}

def installSystemVmTemplate(target, secondaryStorage) {
  ssh(target, 'mkdir -p scripts/storage')
  scp('scripts/storage/secondary', "${target}:./scripts/storage/")
  ssh(target, 'chmod +x scripts/storage/secondary/*')
  ssh(target, "bash -x ./scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondaryStorage} -f /data/templates/systemvm64template-master-4.6.0-kvm.qcow2 -h kvm -o localhost -r root -e qcow2 -F")
  echo '==> SystemVM installed'
}

def deployRpm(target) {
  scp('dist/rpmbuild/RPMS/x86_64/cloudstack-agent-*.rpm', "${target}:./")
  scp('dist/rpmbuild/RPMS/x86_64/cloudstack-common-*.rpm', "${target}:./")
  def hostCommands = [
    'yum -q -y remove cloudstack-common',
    'rm -f /etc/cloudstack/agent/agent.properties',
    'yum -q -y localinstall cloudstack-agent* cloudstack-common*'
  ]
  makeBashScript('deploy_rpm.sh', hostCommands)
  scp('deploy_rpm.sh', "${target}:./")
  ssh(target, './deploy_rpm.sh')
  echo "==> RPM deployed on ${target}"
}

def deployRpmsInParallel(hosts, executor, parentJob, parentJobBuild, filesToCopy) {
  def branchNameFunction = { h -> "Deploying RPM in ${h}" }
  def deployRpmFunction  = { h ->
    node(executor) {
      copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy)
      deployRpm("root@${h}")
    }
  }
  parallel buildParallelBranches(hosts, branchNameFunction, deployRpmFunction)
}

def buildParallelBranches(elements, branchNameFunction, actionFunction) {
  def branches = [failFast: true]
  for (int i = 0; i < elements.size(); i++) {
    def element = elements.getAt(i)
    def branchName = branchNameFunction(element)
    branches.put(branchName, {
      actionFunction(element)
    })
  }
  return branches
}

def updateManagementServerIp(configFile, vmIp) {
  sh "sed -i 's/\"mgtSvrIp\": \"localhost\"/\"mgtSvrIp\": \"${vmIp}\"/' ${configFile}"
}

def waitForMysqlToBeRunning(hostname) {
  waitForPort(hostname, 3306, 'tcp')
  echo '==> MySQL Ready'
}

def waitForPort(hostname, port, transport) {
  sh "while ! nmap -Pn -p${port} ${hostname} | grep '${port}/${transport} open' 2>&1 > /dev/null; do sleep 1; done"
}

def scp(source, target) {
  sh "scp -i ~/.ssh/mccd-jenkins.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q -r ${source} ${target}"
}

def ssh(target, command) {
  sh "ssh -i ~/.ssh/mccd-jenkins.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q ${target} \"${command}\""
}

def mysqlScript(host, user, pass, db, script) {
  def passOption = pass !=  '' ? "-p${pass}" : ''
  sh "mysql -h${host} -u ${user} ${passOption} ${db} < ${script}"
}

def makeBashScript(name, commands) {
  writeFile file: name, text: '#! /bin/bash\n\n' + commands.join(';\n')
  sh "chmod +x ${name}"
}
