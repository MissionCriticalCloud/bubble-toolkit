import hudson.plugins.copyartifact.SpecificBuildSelector

// Job Parameters
def nodeExecutor         = executor
def parentJob            = parent_job
def parentJobBuild       = parent_job_build
def marvinTestsWithHw    = (marvin_tests_with_hw.split(' ') as List)
def marvinTestsWithoutHw = (marvin_tests_without_hw.split(' ') as List)
def marvinConfigFile     = marvin_config_file

def MARVIN_DIST_FILE = [ 'tools/marvin/dist/Marvin-*.tar.gz' ]

def MARVIN_SCRIPTS = [
  'test/integration/',
  'tools/travis/xunit-reader.py'
]

node(nodeExecutor) {
  def filesToCopy = MARVIN_DIST_FILE + MARVIN_SCRIPTS + [marvinConfigFile]
  copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy)
  archive filesToCopy.join(', ')

  stash name: 'marvin', includes: filesToCopy.join(', ')

  parallel 'Marvin tests with hardware': {
    runMarvinTestsInParallel(marvinConfigFile, marvinTestsWithHw, true)
  }, 'Marvin tests without hardware': {
    runMarvinTestsInParallel(marvinConfigFile, marvinTestsWithoutHw, false)
  }

  unarchive mapping: ['integration-test-results/': '.']
  try {
    sh 'python tools/travis/xunit-reader.py integration-test-results/'
  } catch(all) {
    echo 'Need to fix tools/travis/xunit-reader.py to not exit != 0'
  }finally {
    step([$class: 'JUnitResultArchiver', testResults: 'integration-test-results/**/test_*.xml'])
  }
}

// ----------------
// Helper functions
// ----------------

// TODO: move to library
def copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy) {
  step ([$class: 'CopyArtifact',  projectName: parentJob,  selector: new SpecificBuildSelector(parentJobBuild), filter: filesToCopy.join(', ')]);
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

def runMarvinTestsInParallel(marvinConfigFile, marvinTests, requireHardware) {
  node(nodeExecutor) {
    unstash 'marvin'
    setupPython {
      installMarvin('tools/marvin/dist/Marvin-*.tar.gz')
      def branchNameFunction     = { t -> "Marvin test: ${t}" }
      def runMarvinTestsFunction = { t -> runMarvinTest(t, marvinConfigFile, requireHardware) }
      def marvinTestBranches = buildParallelBranches(marvinTests, branchNameFunction, runMarvinTestsFunction)
      parallel(marvinTestBranches)
    }
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
