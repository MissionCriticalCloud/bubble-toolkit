def DEFAULT_GIT_REPO_URL         = 'https://github.com/schubergphilis/MCCloud.git/'
def DEFAULT_GIT_REPO_BRANCH      = 'master'
def DEFAULT_GIT_REPO_CREDENTIALS = '298a5b23-7bfc-4b68-82aa-ca44465b157d'

def EXECUTOR = 'executor-mct'

def MARVIN_TESTS_WITH_HARDWARE = [
  'component/test_vpc_redundant',
  'component/test_routers_iptables_default_policy',
  'component/test_routers_network_ops',
  'component/test_vpc_router_nics',
  'smoke/test_loadbalance',
  'smoke/test_internal_lb',
  'smoke/test_ssvm'
]

def MARVIN_TESTS_WITHOUT_HARDWARE = [
  'smoke/test_routers',
  'smoke/test_network_acl',
  'smoke/test_privategw_acl',
  'smoke/test_reset_vm_on_reboot',
  'smoke/test_vm_life_cycle',
  'smoke/test_vpc_vpn',
  'smoke/test_service_offerings',
  'component/test_vpc_offerings',
  'component/test_vpc_routers'
]

def MARVIN_CONFIG_FILE = 'mct-zone1-kvm1-kvm2.cfg'

def FOLDERS = [
  'mccloud',
  'mccloud-dev'
]

FOLDERS.each { folder_name ->
  folder(folder_name)

  def aggregatodJobName     = "${folder_name}/mct-aggregator"
  def checkoutJobName       = "${folder_name}/mct-checkout"
  def deployInfraJobName    = "${folder_name}/mct-deploy-infra"
  def deployDcJobName       = "${folder_name}/mct-deploy-data-center"
  def runMarvinTestsJobName = "${folder_name}/mct-run-marvin-tests"
  def cleanUpInfraJobName   = "${folder_name}/mct-cleanup-infra"

  workflowJob(aggregatodJobName) {
    quietPeriod(60)
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    parameters {
      textParam('git_repo_url', DEFAULT_GIT_REPO_URL, 'The git repository url ')
      textParam('sha1', DEFAULT_GIT_REPO_BRANCH, 'The git branch (or commit hash)')
      credentialsParam('git_repo_credentials') {
        type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
        defaultValue(DEFAULT_GIT_REPO_CREDENTIALS)
        description('Username/password credentials for git repo')
      }
      textParam('marvin_tests_with_hw', MARVIN_TESTS_WITH_HARDWARE.join(' '), 'Marvin tests tagged as require_hardware=true')
      textParam('marvin_tests_without_hw', MARVIN_TESTS_WITHOUT_HARDWARE.join(' '), 'Marvin tests tagged as require_hardware=false')
      textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
    }
    definition {
      cps {
        script(readFileFromWorkspace('ci/mct-workflow-aggregator.groovy'))
      }
    }
  }

  workflowJob(checkoutJobName) {
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    parameters {
      textParam('git_repo_url', DEFAULT_GIT_REPO_URL, 'The git repository url ')
      textParam('sha1', DEFAULT_GIT_REPO_BRANCH, 'The git branch (or commit hash)')
      credentialsParam('git_repo_credentials') {
        type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
        defaultValue(DEFAULT_GIT_REPO_CREDENTIALS)
        description('Username/password credentials for git repo')
      }
    }
    definition {
      cps {
        script(readFileFromWorkspace('ci/mct-workflow-checkout-and-build-job.groovy'))
      }
    }
  }

  workflowJob(deployInfraJobName) {
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    parameters {
      textParam('executor', EXECUTOR, 'The executor label')
      textParam('parent_job', checkoutJobName, 'The parent job name')
      textParam('parent_job_build', '', 'The parent job build number')
      textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
    }
    definition {
      cps {
        script(readFileFromWorkspace('ci/mct-workflow-deploy-infra-job.groovy'))
      }
    }
  }

  workflowJob(deployDcJobName) {
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    parameters {
      textParam('executor', EXECUTOR, 'The executor label')
      textParam('parent_job', deployInfraJobName, 'The parent job name')
      textParam('parent_job_build', '', 'The parent job build number')
      textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
    }
    definition {
      cps {
        script(readFileFromWorkspace('ci/mct-workflow-deploy-data-center-job.groovy'))
      }
    }
  }


  workflowJob(runMarvinTestsJobName) {
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    parameters {
      textParam('executor', EXECUTOR, 'The executor label')
      textParam('parent_job', deployDcJobName, 'The parent job name')
      textParam('parent_job_build', '', 'The parent job build number')
      textParam('marvin_tests_with_hw', MARVIN_TESTS_WITH_HARDWARE.join(' '), 'Marvin tests tagged as require_hardware=true')
      textParam('marvin_tests_without_hw', MARVIN_TESTS_WITHOUT_HARDWARE.join(' '), 'Marvin tests tagged as require_hardware=false')
      textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
    }
    definition {
      cps {
        script(readFileFromWorkspace('ci/mct-workflow-run-marvin-tests-job.groovy'))
      }
    }
  }

  workflowJob(cleanUpInfraJobName) {
    logRotator {
      numToKeep(5)
      artifactNumToKeep(5)
    }
    parameters {
      textParam('executor', EXECUTOR, 'The executor label')
      textParam('parent_job', runMarvinTestsJobName, 'The parent job name')
      textParam('parent_job_build', '', 'The parent job build number')
      textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
    }
    definition {
      cps {
        script(readFileFromWorkspace('ci/mct-workflow-cleanup-infra-job.groovy'))
      }
    }
  }
}
