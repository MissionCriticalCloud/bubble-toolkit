import hudson.plugins.copyartifact.SpecificBuildSelector

// Job Parameters
def nodeExecutor         = executor
def parentJob            = parent_job
def parentJobBuild       = parent_job_build
def marvinTestsWithHw    = (marvin_tests_with_hw.split(' ') as List)
def marvinTestsWithoutHw = (marvin_tests_without_hw.split(' ') as List)
def marvinConfigFile     = marvin_config_file

def MARVIN_DIST_FILE = [ 'tools/marvin/dist/Marvin-*.tar.gz' ]

def MARVIN_SCRIPTS = [ 'test/integration/' ]

// each test will grab a node(nodeExecutor)
node('executor') {
  def filesToCopy = MARVIN_DIST_FILE + MARVIN_SCRIPTS + [marvinConfigFile]
  copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy)
  archive filesToCopy.join(', ')

  stash name: 'marvin', includes: filesToCopy.join(', ')

  runMultipleMarvinTests(marvinTestsWithHw, marvinConfigFile, true, nodeExecutor)
  runMultipleMarvinTests(marvinTestsWithHw, marvinConfigFile, false, nodeExecutor)

  unarchive mapping: ['nosetests.xml': '.']
  step([$class: 'JUnitResultArchiver', testResults: 'nosetests.xml'])
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

def runMarvinTestsInParallel(marvinConfigFile, marvinTests, requireHardware, nodeExecutor) {  //def branchNameFunction     = { t -> "Marvin test: ${t}" }
  def branchNameFunction     = { t -> "Marvin test: ${t}" }
  def runMarvinTestsFunction = { t -> runMarvinTest(t, marvinConfigFile, requireHardware, nodeExecutor) }
  def marvinTestBranches = buildParallelBranches(marvinTests, branchNameFunction, runMarvinTestsFunction)
  parallel(marvinTestBranches)
}

def runMarvinTest(testPath, configFile, requireHardware, nodeExecutor) {
  node(nodeExecutor) {
    sh 'rm -rf ./*'
    unstash 'marvin'
    setupPython {
      installMarvin('tools/marvin/dist/Marvin-*.tar.gz')
      sh 'mkdir -p integration-test-results/smoke/misc integration-test-results/component'
      try {
        sh "nosetests --with-xunit --xunit-file=integration-test-results/${testPath}.xml --with-marvin --marvin-config=${configFile} test/integration/${testPath}.py -s -a tags=advanced,required_hardware=${requireHardware}"
      } catch(e) {
        echo "Test ${testPath} was not successful"
      }
      archive 'integration-test-results/'

      def testName = testPath.replaceFirst('^.*/','')
      sh "mkdir -p MarvinLogs/${testPath}"
      sh "cp -rf /tmp/MarvinLogs/${testName}_*/* MarvinLogs/${testPath}/"
      archive 'MarvinLogs/'
    }
  }
}

def runMultipleMarvinTests(tests, configFile, requireHardware, nodeExecutor) {
  def fullPathTests = []
  for(int i = 0; i < tests.size; i++) {
    fullPathTests.add('test/integration/' + tests.getAt(i) + '.py')
  }

  node(nodeExecutor) {
    sh 'rm -rf /tmp/MarvinLogs'
    sh 'rm -rf ./*'
    unstash 'marvin'
    setupPython {
      installMarvin('tools/marvin/dist/Marvin-*.tar.gz')
      sh 'mkdir -p integration-test-results/smoke/misc integration-test-results/component'
      try {
        sh "nosetests --with-xunit --with-marvin --marvin-config=${configFile} -s -a tags=advanced,required_hardware=${requireHardware} ${fullPathTests.join(' ')}"
      } catch(e) {
        echo "Test run was not successful"
      }
      archive 'nosetests.xml'

      sh "mkdir -p MarvinLogs/"
      sh "cp -rf /tmp/MarvinLogs/* MarvinLogs/"
      archive 'MarvinLogs/'
    }
  }
}

def buildParallelBranches(elements, branchNameFunction, actionFunction) {
  def branches = [:]
  for (int i = 0; i < elements.size(); i++) {
    def element = elements.getAt(i)
    def branchName = branchNameFunction(element)
    branches.put(branchName, {
      actionFunction(element)
    })
  }
  return branches
}
