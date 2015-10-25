import hudson.plugins.copyartifact.SpecificBuildSelector

// Job Parameters
def nodeExecutor     = executor
def parentJob        = parent_job
def parentJobBuild   = parent_job_build
def marvinConfigFile = marvin_config_file

def MARVIN_DIST_FILE = [ 'tools/marvin/dist/Marvin-*.tar.gz' ]

node(nodeExecutor) {
  def filesToCopy = MARVIN_DIST_FILE
  copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy)

  sh  "cp /data/shared/marvin/${marvinConfigFile} ./"
  updateManagementServerIp(marvinConfigFile, 'cs1')

  setupPython {
    installMarvin('tools/marvin/dist/Marvin-*.tar.gz')
    waitForManagementServer('cs1')
    deployDataCenter(marvinConfigFile)
    waitForSystemVmTemplates()
  }
}

// ----------------
// Helper functions
// ----------------

// TODO: move to library
def copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy) {
  step ([$class: 'CopyArtifact',  projectName: parentJob,  selector: new SpecificBuildSelector(parentJobBuild), filter: filesToCopy.join(', ')]);
}

def updateManagementServerIp(configFile, vmIp) {
  sh "sed -i 's/\"mgtSvrIp\": \"localhost\"/\"mgtSvrIp\": \"${vmIp}\"/' ${configFile}"
}

def waitForManagementServer(hostname) {
  waitForPort(hostname, 8096, 'tcp')
  echo '==> Management Server responding'
}

def waitForPort(hostname, port, transport) {
  sh "while ! nmap -Pn -p${port} ${hostname} | grep '${port}/${transport} open' 2>&1 > /dev/null; do sleep 1; done"
}

def setupPython(action) {
  sh 'virtualenv --system-site-packages venv'
  sh 'unset PYTHONHOME'
  withEnv(environmentForMarvin(pwd())) {
    action()
  }
}

def environmentForMarvin(dir) {
  [
    "VIRTUAL_ENV=${dir}/venv",
    "PATH=${dir}/venv/bin:${env.PATH}"
  ]
}

def installMarvin(marvinDistFile) {
  sh "pip install --upgrade ${marvinDistFile}"
  sh 'pip install nose --upgrade --force'
}


def deployDataCenter(configFile) {
  sh "python -m marvin.deployDataCenter -i ${configFile}"
  echo '==> Data Center deployed'
}

def waitForSystemVmTemplates() {
  ssh('root@cs1', 'bash -x /data/shared/helper_scripts/cloudstack/wait_template_ready.sh')
}

def ssh(target, command) {
  sh "ssh -i ~/.ssh/mccd-jenkins.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q ${target} \"${command}\""
}
