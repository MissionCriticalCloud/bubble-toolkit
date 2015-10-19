// Job Parameters
def cloudstackApiKeyCredentialId    = cloudstack_api_key_credential_id
def cloudstackSecretKeyCredentialId = cloudstack_secret_key_credential_id

def tests = [
  'smoke/test_affinity_groups',
  'smoke/test_primary_storage',
  'smoke/test_deploy_vms_with_varied_deploymentplanners',
  'smoke/test_disk_offerings',
  'smoke/test_global_settings',
  'smoke/test_multipleips_per_nic',
  'smoke/test_portable_publicip',
  'smoke/test_privategw_acl',
  'smoke/test_public_ip_range',
  'smoke/test_pvlan',
  'smoke/test_regions',
  'smoke/test_network',
  'smoke/test_reset_vm_on_reboot',
  'smoke/test_resource_detail',
  'smoke/test_routers',
  'smoke/test_guest_vlan_range',
  'smoke/test_iso',
  'smoke/test_non_contigiousvlan',
  'smoke/test_secondary_storage',
  'smoke/test_service_offerings',
  'smoke/test_ssvm',
  'smoke/test_templates',
  'smoke/test_over_provisioning',
  'smoke/test_volumes',
  'smoke/test_vpc_vpn',
  'smoke/misc/test_deploy_vm',
  'smoke/test_vm_life_cycle',
  'component/test_mm_max_limits',
  'component/test_acl_isolatednetwork_delete',
  'component/test_mm_domain_limits',
  'component/test_acl_listsnapshot',
  'component/test_acl_listvm',
  'component/test_acl_sharednetwork_deployVM-impersonation',
  'component/test_acl_sharednetwork',
  'component/test_snapshots',
  'component/test_acl_listvolume'
]

def configFile = 'setup/dev/advanced.cfg'

def marvinDistFile = 'tools/marvin/dist/Marvin-*.tar.gz'

node('executor') {
  stage 'Stage :: Checkout & Build'
  checkout scm: [$class: 'GitSCM', branches:          [[name: "${sha1}"]],
                                   userRemoteConfigs: [[url:  "${git_repo_url}", credentialsId: "${git_repo_credentials}"]]]

  mvn 'clean install -Pdeveloper,systemvm -Dsimulator'

  setupPython {
    installMarvin(marvinDistFile)
    def vagrantAction = { runSimulatorTests(tests, marvinDistFile, configFile) }
    setupVagrant(vagrantAction, cloudstackApiKeyCredentialId, cloudstackSecretKeyCredentialId)
  }
  reportResults()
}

// --------------
// helper methods
// --------------

def runSimulatorTests(tests, marvinDistFile, configFile) {
  stage 'Stage :: Running Management Server (with Simulator)'
  try {
    vagrant('up')
    def vagrantVmIp = getManagementServerIp()
    updateManagementServerIp(configFile, vagrantVmIp)
    waitForManagementServer(vagrantVmIp)
    deployDataCenter(configFile)
    stash name: 'marvin', includes: "${marvinDistFile}, test/integration/, tools/travis/xunit-reader.py, ${configFile}"
    stage 'Stage :: Running Marvin Tests (against Simulator)'
    parallel(buildParallelTestBranches(tests, marvinDistFile, configFile))
  } finally {
    vagrant('destroy -f')
  }
}

def reportResults() {
  unarchive mapping: ['integration-test-results/': '.']
  try {
    sh 'python tools/travis/xunit-reader.py integration-test-results/'
  } finally {
    step([$class: 'JUnitResultArchiver', testResults: 'integration-test-results/**/test_*.xml'])
  }
}

def getManagementServerIp() {
  vagrant('ssh-config | grep HostName | cut -f4 -d\' \' > .vagrant_vm_ip')
  def vagrantVmIp = readFile('.vagrant_vm_ip').trim()
  sh 'rm .vagrant_vm_ip'
  vagrantVmIp
}

def updateManagementServerIp(configFile, vmIp) {
  sh "sed -i 's/\'mgtSvrIp\': \'localhost\'/\'mgtSvrIp\': \'${vmIp}\'/' ${configFile}"
}
def waitForManagementServer(vmIp) {
  sleep 120 // more or less the time is takes for the management server to be up
  sh "while ! nmap -Pn -p8096 ${vmIp} | grep '8096/tcp open' 2>&1 > /dev/null; do sleep 1; done"
}

def installMarvin(marvinDistFile) {
  sh "pip install --upgrade ${marvinDistFile}"
}

def deployDataCenter(configFile) {
  stage 'Stage :: Deploy Data Center'
  sh "python -m marvin.deployDataCenter -i ${configFile}"
  sleep 60 // hoping templates will be ready
}

def setupPython(action) {
  sh 'virtualenv --system-site-packages venv'
  sh 'unset PYTHONHOME'
  withEnv(environmentForMarvin(pwd())) {
    action()
  }
}

def setupVagrant(action, cloudstackApiKeyCredentialId, cloudstackSecretKeyCredentialId) {
  withEnv(environmentForVagrant()) {
    withCredentials(credentialsForVagrant(cloudstackApiKeyCredentialId, cloudstackSecretKeyCredentialId)) {
      action()
    }
  }
}

def buildParallelTestBranches(tests, marvinDistFile, configFile) {
  def branches = [:]
  for (int i = 0; i < tests.size(); i++) {
    def testPath = tests.get(i)
    branches.put(testPath, {
      ws(testPath) {
        node('executor') {
          sh 'rm -rf *'
          setupPython({ runMarvinTest(testPath, marvinDistFile, configFile) })
        }
      }
    })
  }
  return branches
}

def runMarvinTest(testPath, marvinDistFile, configFile) {
  unstash 'marvin'
  installMarvin(marvinDistFile)
  sh 'mkdir -p integration-test-results/smoke/misc integration-test-results/component'
  try {
    sh "nosetests --with-xunit --xunit-file=integration-test-results/${testPath}.xml --with-marvin --marvin-config=${configFile} test/integration/${testPath}.py -s -a tags=advanced,required_hardware=false --zone=Sandbox-simulator --hypervisor=simulator"
  } catch(e) {
    echo "Test ${testPath} was not successful"
  }
  archive '/tmp/MarvinLogs/'
  archive 'integration-test-results/'
}

def environmentForMarvin(dir) {
  [
    "VIRTUAL_ENV=${dir}/venv",
    "PATH=${dir}/venv/bin:${env.PATH}"
  ]
}

def environmentForVagrant() {
  [
   'VAGRANT_VAGRANTFILE=tools/jenkins/Vagrantfile.management_server'
  ]
}

def credentialsForVagrant(cloudstackApiKeyCredentialId, cloudstackSecretKeyCredentialId) {
  [
    [$class: 'StringBinding', variable: 'CLOUDSTACK_API_KEY',    credentialsId: cloudstackApiKeyCredentialId],
    [$class: 'StringBinding', variable: 'CLOUDSTACK_SECRET_KEY', credentialsId: cloudstackSecretKeyCredentialId]
  ]
}

def vagrant(action) {
  sh "vagrant ${action}"
}

def mvn(args) {
  sh "${tool 'M3'}/bin/mvn ${args}"
}
