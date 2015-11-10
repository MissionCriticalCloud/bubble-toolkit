def DEFAULT_GITHUB_REPO     = 'apache/cloudstack'
def DEFAULT_GIT_REPO_BRANCH = 'remotes/origin/pr/*/head'

def EXECUTOR = 'executor-mct'

def MARVIN_TESTS_WITH_HARDWARE = [
  'component/test_vpc_redundant.py',
  'component/test_routers_iptables_default_policy.py',
  'component/test_routers_network_ops.py',
  'component/test_vpc_router_nics.py',
  'smoke/test_loadbalance.py',
  'smoke/test_internal_lb.py',
  'smoke/test_ssvm.py',
  'smoke/test_network.py',
  'smoke/test_vpc_vpn.py'
]

def MARVIN_TESTS_WITHOUT_HARDWARE = [
  'component/test_vpc_offerings.py',
  'component/test_vpc_routers.py',
  'smoke/test_routers.py',
  'smoke/test_network_acl.py',
  'smoke/test_privategw_acl.py',
  'smoke/test_reset_vm_on_reboot.py',
  'smoke/test_vm_life_cycle.py',
  'smoke/test_service_offerings.py',
  'smoke/test_network.py'
]

def MARVIN_CONFIG_FILE = 'mct-zone1-kvm1-kvm2.cfg'

def CHECKOUT_JOB_ARTIFACTS = [
  'client/target/cloud-client-ui-*.war',
  'client/target/utilities/',
  'client/target/conf/',
  'cloudstack-*.rpm',
  'tools/marvin/dist/Marvin-*.tar.gz',
  'setup/db/db/',
  'setup/db/create-*.sql',
  'setup/db/templates*.sql',
  'developer/developer-prefill.sql',
  'scripts/storage/secondary/',
  'test/integration/'
]

def MARVIN_TESTS_JOB_ARTIFACTS = [
  'nosetests-*.xml',
  '/tmp/MarvinLogs/'
]

def CLEAN_UP_JOB_ARTIFACTS = [
  'vmops.log*',
  'api.log*',
  'kvm1-agent-logs/',
  'kvm2-agent-logs/'
]

def FOLDERS = [
  'acs-ci-build',
  'acs-ci-build-dev'
]

FOLDERS.each { folderName ->
  folder(folderName)

  def fullBuildJobName               = "${folderName}/001-full-build"
  def checkoutJobName                = "${folderName}/002-checkout-and-build"
  def deployInfraJobName             = "${folderName}/003-deploy-infra"
  def deployDcJobName                = "${folderName}/004-deploy-data-center"
  def runMarvinTestsWithHwJobName    = "${folderName}/005-run-marvin-tests-with-hardware"
  def runMarvinTestsWithoutHwJobName = "${folderName}/005-run-marvin-tests-without-hardware"
  def cleanUpJobName                 = "${folderName}/006-cleanup"
  def runMarvinTestsJobName          = "${folderName}/901-run-marvin-tests"

  multiJob(fullBuildJobName) {
    parameters {
      stringParam('sha1', DEFAULT_GIT_REPO_BRANCH, 'Branch to be checked out and built')
    }
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(1)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    scm {
      git {
        remote {
          github(DEFAULT_GITHUB_REPO, 'https')
          name('origin')
          refspec('+refs/pull/*:refs/remotes/origin/pr/* +refs/heads/*:refs/remotes/origin/*')
        }
        branch('${sha1}')
        shallowClone(true)
        clean(true)
      }
    }
    steps {
      phase('Checkout Code, Build and Package') {
        phaseJob(checkoutJobName) {
          currentJobParameters(true)
          parameters {
            sameNode()
            gitRevision(false)
          }
        }
      }
      phase('Deploy Cloud Infrastructure') {
        phaseJob(deployInfraJobName) {
          parameters {
            sameNode()
          }
        }
      }
      phase('Deploy Data Center') {
        phaseJob(deployDcJobName) {
          parameters {
            sameNode()
          }
        }
      }
      phase('Run Marvin Tets') {
        phaseJob(runMarvinTestsWithHwJobName) {
          parameters {
            sameNode()
          }
        }
        phaseJob(runMarvinTestsWithoutHwJobName) {
          parameters {
            sameNode()
          }
        }
      }
      phase('Collect Artifacts and Clean Up') {
        phaseJob(cleanUpJobName) {
          parameters {
            sameNode()
          }
        }
      }
      copyArtifacts(checkoutJobName) {
        includePatterns(CHECKOUT_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
      copyArtifacts(runMarvinTestsWithHwJobName) {
        includePatterns(MARVIN_TESTS_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
      copyArtifacts(runMarvinTestsWithoutHwJobName) {
        includePatterns(MARVIN_TESTS_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
      copyArtifacts(cleanUpJobName) {
        includePatterns(CLEAN_UP_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
    }
    publishers {
      archiveArtifacts {
        pattern((CHECKOUT_JOB_ARTIFACTS + MARVIN_TESTS_JOB_ARTIFACTS + MARVIN_TESTS_JOB_ARTIFACTS + CLEAN_UP_JOB_ARTIFACTS).join(', '))
      }
      archiveJunit('nosetests-*.xml') {
        retainLongStdout()
        testDataPublishers {
          publishTestStabilityData()
        }
      }
    }
  }

  freeStyleJob(checkoutJobName) {
    parameters {
      stringParam('sha1', DEFAULT_GIT_REPO_BRANCH, 'Branch to be checked out and built')
    }
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(1)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    scm {
      git {
        remote {
          github(DEFAULT_GITHUB_REPO, 'https')
          name('origin')
          refspec('+refs/pull/*:refs/remotes/origin/pr/* +refs/heads/*:refs/remotes/origin/*')
        }
        branch('${sha1}')
        shallowClone(true)
        clean(true)
      }
    }
    steps {
      maven {
        goals('clean')
        goals('install')
        goals('-P developer,systemvm')
        goals('-T 4')
        mavenOpts('-Xms256m')
        mavenOpts('-Xmx1024m')
        mavenInstallation('Maven 3.1.1')
      }
      shell('/data/shared/ci/ci-package-rpms.sh')
    }
    publishers {
      archiveArtifacts {
        pattern(CHECKOUT_JOB_ARTIFACTS.join(', '))
      }
      archiveJunit('**/target/surefire-reports/*.xml') {
        retainLongStdout()
        testDataPublishers {
          publishTestStabilityData()
        }
      }
    }
  }

  freeStyleJob(deployInfraJobName) {
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(1)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    steps {
      shell('rm -rf ./*')
      copyArtifacts(checkoutJobName) {
        includePatterns(CHECKOUT_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
      shell('/data/shared/ci/ci-deploy-infra.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg')
    }
  }

  freeStyleJob(deployDcJobName) {
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(1)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    steps {
      shell('rm -rf ./*')
      copyArtifacts(checkoutJobName) {
        includePatterns('tools/marvin/dist/Marvin-*.tar.gz')
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
      shell('/data/shared/ci/ci-deploy-data-center.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg')
    }
  }

  freeStyleJob(runMarvinTestsJobName) {
    parameters {
      stringParam('REQUIRED_HARDWARE', null, 'Flag passed to Marvin to select test cases to execute')
      textParam('TESTS', '', 'Set of Marvin tests to execute')
    }
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(2)
    }
    logRotator {
      numToKeep(10)
      artifactNumToKeep(10)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    steps {
      shell('rm -rf ./*')
      copyArtifacts(checkoutJobName) {
        includePatterns('test/integration/')
        fingerprintArtifacts(true)
        buildSelector {
          multiJobBuild()
        }
      }
      shell('/data/shared/ci/ci-run-marvin-tests.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -h ${REQUIRED_HARDWARE} "${TESTS}"')
    }
    publishers {
      archiveArtifacts {
        pattern('nosetests-*.xml')
      }
    }
  }

  freeStyleJob(runMarvinTestsWithHwJobName) {
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(2)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    steps {
      shell('rm -rf ./*')
      downstreamParameterized {
        trigger(runMarvinTestsJobName, 'ALWAYS', false) {
          block {
            buildStepFailure('never')
            failure('never')
            unstable('never')
          }
          parameters {
            predefinedProp('REQUIRED_HARDWARE', 'true')
            predefinedProp('TESTS', MARVIN_TESTS_WITH_HARDWARE.join(' '))
          }
          sameNode()
        }
      }
      copyArtifacts(runMarvinTestsJobName) {
        includePatterns(MARVIN_TESTS_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          buildNumber("\${TRIGGERED_BUILD_NUMBER_${runMarvinTestsJobName.replaceAll('[^A-Za-z0-9]', '_')}}")
        }
      }
    }
    publishers {
      archiveArtifacts {
        pattern(MARVIN_TESTS_JOB_ARTIFACTS.join(', '))
      }
    }
  }

  freeStyleJob(runMarvinTestsWithoutHwJobName) {
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(2)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    steps {
      shell('rm -rf ./*')
      downstreamParameterized {
        trigger(runMarvinTestsJobName, 'ALWAYS', false) {
          block {
            buildStepFailure('never')
            failure('never')
            unstable('never')
          }
          parameters {
            predefinedProp('REQUIRED_HARDWARE', 'false')
            predefinedProp('TESTS', MARVIN_TESTS_WITHOUT_HARDWARE.join(' '))
          }
          sameNode()
        }
      }
      copyArtifacts(runMarvinTestsJobName) {
        includePatterns(MARVIN_TESTS_JOB_ARTIFACTS.join(', '))
        fingerprintArtifacts(true)
        buildSelector {
          buildNumber("\${TRIGGERED_BUILD_NUMBER_${runMarvinTestsJobName.replaceAll('[^A-Za-z0-9]', '_')}}")
        }
      }
    }
    publishers {
      archiveArtifacts {
        pattern(MARVIN_TESTS_JOB_ARTIFACTS.join(', '))
      }
    }
  }

  freeStyleJob(cleanUpJobName) {
    concurrentBuild()
    label(EXECUTOR)
    throttleConcurrentBuilds {
      maxPerNode(1)
    }
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    wrappers {
      colorizeOutput('xterm')
      timestamps()
    }
    steps {
      shell('rm -rf ./*')
      shell('/data/shared/ci/ci-cleanup.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg')
    }
    publishers {
      archiveArtifacts {
        pattern(CLEAN_UP_JOB_ARTIFACTS.join(', '))
      }
    }
  }
}
