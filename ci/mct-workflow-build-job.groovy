import groovy.json.JsonSlurper;

// Job Parameters
def gitRepoUrl           = git_repo_url
def gitRepoCredentials   = git_repo_credentials
def gitBranch            = sha1
def marvinTestsWithHw    = (marvin_tests_with_hw.split(' ') as List)
def marvinTestsWithoutHw = (marvin_tests_without_hw.split(' ') as List)
def marvinConfigFile     = marvin_config_file

node('executor') {
  // TODO: these should not be hardcoded. Either read them from the Marvin config
  //       or make these job parameters
  def hosts = ['kvm1', 'kvm2']
  def secondaryStorage = '/data/storage/secondary/MCCT-SHARED-1'

  checkoutAndBuild(gitRepoUrl, gitBranch, gitRepoCredentials)

  try {
    deployInfra(hosts, secondaryStorage, marvinConfigFile)
    deployManagementServer(marvinConfigFile)
    parallel 'Marvin tests with hardware': {
      runMarvinTests(marvinConfigFile, marvinTestsWithHw, true)
    }, 'Marvin tests without hardware': {
      runMarvinTests(marvinConfigFile, marvinTestsWithoutHw, false)
    }
  } finally {
    cleanUp()
  }

  reportResults()
}

// --------------
// helper methods
// --------------

def checkoutAndBuild(gitRepoUrl, gitBranch, gitRepoCredentials) {
  checkout scm: [$class: 'GitSCM', branches:          [[name: gitBranch]],
                                   userRemoteConfigs: [[url:  gitRepoUrl, credentialsId: gitRepoCredentials]]]

  def projectVersion = version()

  mvn 'clean install -Pdeveloper,systemvm -T4'
  reportJUnitResult('**/target/surefire-reports/*.xml')
  packageRpm('centos7')
  archive "client/target/cloud-client-ui-${projectVersion}.war"
  archive "dist/rpmbuild/RPMS/x86_64/cloudstack-agent-${projectVersion}*.rpm"
  archive "dist/rpmbuild/RPMS/x86_64/cloudstack-common-${projectVersion}*.rpm"
  archive "tools/marvin/dist/Marvin-${projectVersion}.tar.gz"

  def dbScripts = [
    'setup/db/db/',
    'setup/db/create-*.sql',
    'setup/db/templates*.sql',
    'developer/developer-prefill.sql'
  ]

  def templateScripts = [
    'scripts/storage/secondary/'
  ]

  def marvinScripts = [
    'test/integration/',
    'tools/travis/xunit-reader.py'
  ]

  stash name: 'db-scripts', includes: dbScripts.join(', ')
  stash name: 'template-scripts', includes: templateScripts.join(', ')
  stash name: 'marvin-scripts', includes: marvinScripts.join(', ')
}

def deployInfra(hosts, secondaryStorage, marvinConfigFile) {
  node('executor-mct') {
    sh  "cp /data/shared/marvin/${marvinConfigFile} ."
    updateManagementServerIp(marvinConfigFile, '192.168.22.61')
    stash name: 'marvin-config', includes: marvinConfigFile

    parallel 'Deploy Management Server': {
      unarchive mapping: ['client/target/': '.']
      unstash 'db-scripts'
      unstash 'template-scripts'
      deployMctCs()
      deployDb()
      installSystemVmTemplate('root@cs1', secondaryStorage)
      deployWar()
    }, 'Deploy Hosts': {
      unarchive mapping: ['dist/rpmbuild/RPMS/x86_64/': '.']
      unarchive mapping: ['tools/marvin/dist/': '.']
      deployHosts(marvinConfigFile)
      deployRpmsInParallel(hosts)
    }, failFast: true
  }
  echo '==> Infrastructure deployed'
}

def deployManagementServer(marvinConfigFile) {
  unstash 'marvin-config'
  setupPython {
    installMarvin('tools/marvin/dist/Marvin-*.tar.gz')
    waitForManagementServer('cs1')
    deployDataCenter(marvinConfigFile)
    waitForSystemVmTemplates()
  }
  echo '==> Mangement Server ready'
}

def runMarvinTests(marvinConfigFile, marvinTests, requireHardware) {
  unarchive mapping: ['tools/marvin/dist/': '.']
  unstash 'marvin-config'
  unstash 'marvin-scripts'
  setupPython {
    installMarvin('tools/marvin/dist/Marvin-*.tar.gz')
    runMarvinTestsInParallel(marvinConfigFile, marvinTests, requireHardware)
  }
}

def cleanUp() {
  node('executor-mct') {
    scp('root@cs1:~tomcat/vmops.log', '.')
    scp('root@cs1:~tomcat/api.log', '.')
    archive 'vmops.log, api.log'
    //cleanUpMct()
  }
}

def reportResults() {
  unarchive mapping: ['integration-test-results/': '.']
  try {
    sh 'python tools/travis/xunit-reader.py integration-test-results/'
  } finally {
    reportJUnitResult('integration-test-results/**/test_*.xml')
  }
}

def reportJUnitResult(resultsMatcher) {
  step([$class: 'JUnitResultArchiver', testResults: resultsMatcher])
}

def updateManagementServerIp(configFile, vmIp) {
  sh "sed -i 's/\"mgtSvrIp\": \"localhost\"/\"mgtSvrIp\": \"${vmIp}\"/' ${configFile}"
}

def removeBuildLineFromRpmSpec(specFile){
  sh "sed -i \"/mvn -Psystemvm -DskipTests/d\" ${specFile} | true"
}

def packageRpm(distribution) {
  dir('packaging') {
    sh "./package.sh -d ${distribution}"
  }
}

def waitForManagementServer(hostname) {
  waitForPort(hostname, 8096, 'tcp')
  echo '==> Management Server responding'
}

def waitForMysqlToBeRunning(hostname) {
  waitForPort(hostname, 3306, 'tcp')
  echo '==> MySQL Ready'
}

def waitForPort(hostname, port, transport) {
  sh "while ! nmap -Pn -p${port} ${hostname} | grep '${port}/${transport} open' 2>&1 > /dev/null; do sleep 1; done"
}

def waitForSystemVmTemplates() {
  ssh('root@cs1', 'bash -x /data/shared/helper_scripts/cloudstack/wait_template_ready.sh')
}

def installMarvin(marvinDistFile) {
  sh "pip install --upgrade ${marvinDistFile}"
  sh 'pip install nose --upgrade --force'
}

def setupPython(action) {
  sh 'virtualenv --system-site-packages venv'
  sh 'unset PYTHONHOME'
  withEnv(environmentForMarvin(pwd())) {
    action()
  }
}

def runMarvinTest(testPath, configFile, requireHardware) {
  sh 'mkdir -p integration-test-results/smoke/misc integration-test-results/component'
  try {
    sh "nosetests --with-xunit --xunit-file=integration-test-results/${testPath}.xml --with-marvin --marvin-config=${configFile} test/integration/${testPath}.py -s -a tags=advanced,required_hardware=${requireHardware}"
  } catch(e) {
    echo "Test ${testPath} was not successful"
  }
  archive '/tmp/MarvinLogs/'
  archive 'integration-test-results/'
}

def runMarvinTestsInParallel(marvinConfigFile, marvinTests, requireHardware) {
  def branchNameFunction     = { t -> "Marvin test: ${t}" }
  def runMarvinTestsFunction = { t -> runMarvinTest(t, marvinConfigFile, requireHardware) }
  def marvinTestBranches = buildParallelBranches(marvinTests, branchNameFunction, runMarvinTestsFunction)
  parallel(marvinTestBranches)
}

def environmentForMarvin(dir) {
  [
    "VIRTUAL_ENV=${dir}/venv",
    "PATH=${dir}/venv/bin:${env.PATH}"
  ]
}

def mvn(args) {
  sh "${tool 'M3'}/bin/mvn ${args}"
}

def deployDataCenter(configFile) {
  sh "python -m marvin.deployDataCenter -i ${configFile}"
  echo '==> Data Center deployed'
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
  sh 'rm -f grant-remote-access.sql extraDbConfig.sql'
  echo '==> DB deployed'
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
  deplyMctVm('-m', "/data/shared/marvin/${marvinConfig}")
  echo '==> kvm1 & kvm2 deployed'
}

def deplyMctVm(option, argument) {
  sh "/data/shared/deploy/kvm_local_deploy.py ${option} ${argument}"
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
  ssh(target, 'deploy_rpm.sh')
  echo "==> RPM deployed on ${target}"
}

def deployRpmsInParallel(hosts) {
  def branchNameFunction = { h -> "Deploying RPM in ${h}" }
  def deployRpmFunction  = { h -> deployRpm("root@${h}") }
  parallel buildParallelBranches(hosts, branchNameFunction, deployRpmFunction)
}

def installSystemVmTemplate(target, secondaryStorage) {
  ssh(target, 'mkdir -p scripts/storage')
  scp('scripts/storage/secondary', "${target}:./scripts/storage/")
  ssh(targte, 'chmod +x scripts/storage/secondary/*')
  ssh(target, "bash -x ./scripts/storage/secondary/cloud-install-sys-tmplt -m ${secondaryStorage} -f /data/templates/systemvm64template-master-4.6.0-kvm.qcow2 -h kvm -o localhost -r root -e qcow2 -F")
  echo '==> SystemVM installed'
}

def cleanUpMct() {
  // TODO: replace hardcoded box names
  sh '/data/vm-easy-deploy/remove_vm.sh -f cs1'
  sh '/data/vm-easy-deploy/remove_vm.sh -f kvm1'
  sh '/data/vm-easy-deploy/remove_vm.sh -f kvm2'
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

def version() {
  def matcher = readFile('pom.xml') =~ '<version>(.+)</version>'
  // first matche will be parent version, so we take the seccond ie, matcher[1]
  matcher ? matcher[1][1] : null
}

def makeBashScript(name, commands) {
  writeFile file: name, text: '#! /bin/bash\n\n' + commands.join(';\n')
  sh "chmod +x ${name}"
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
