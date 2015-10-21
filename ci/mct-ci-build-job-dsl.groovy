def DEFAULT_GIT_REPO_URL    = 'https://github.com/schubergphilis/MCCloud.git/'
def DEFAULT_GIT_REPO_BRANCH = 'master'
def DEFAULT_GIT_REPO_CREDENTIALS   = '298a5b23-7bfc-4b68-82aa-ca44465b157d'

def MARVIN_TESTS_WITH_HARDWARE = [
  'component/test_vpc_redundant',
  'component/test_routers_iptables_default_policy',
  'component/test_routers_network_ops',
  'component/test_vpc_router_nics',
  'smoke/test_loadbalance'
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

def FOLDER_NAME = 'mccloud'

def AGGREGATOR_JOB_NAME       = "${FOLDER_NAME}/mct-aggregator"
def CHECKOUT_JOB_NAME         = "${FOLDER_NAME}/mct-checkout"
def DEPLOY_INFRA_JOB_NAME     = "${FOLDER_NAME}/mct-deploy-infra"
def DEPLOY_DC_JOB_NAME        = "${FOLDER_NAME}/mct-deploy-data-center"
def RUN_MARVIN_TESTS_JOB_NAME = "${FOLDER_NAME}/mct-run-marvin-tests"
def CLEANUP_INFRA_JOB_NAME    = "${FOLDER_NAME}/mct-cleanup-infra"


folder(FOLDER_NAME)

workflowJob(AGGREGATOR_JOB_NAME) {
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

workflowJob(CHECKOUT_JOB_NAME) {
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

workflowJob(DEPLOY_INFRA_JOB_NAME) {
  parameters {
    textParam('parent_job', CHECKOUT_JOB_NAME, 'The parent job name')
    textParam('parent_job_build', '', 'The parent job build number')
    textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
  }
  definition {
    cps {
      script(readFileFromWorkspace('ci/mct-workflow-cleanup-infra-job.groovy'))
    }
  }
}

workflowJob(DEPLOY_DC_JOB_NAME) {
  parameters {
    textParam('parent_job', DEPLOY_INFRA_JOB_NAME, 'The parent job name')
    textParam('parent_job_build', '', 'The parent job build number')
    textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
  }
  definition {
    cps {
      script(readFileFromWorkspace('ci/mct-workflow-deploy-data-center-job.groovy'))
    }
  }
}


workflowJob(RUN_MARVIN_TESTS_JOB_NAME) {
  parameters {
    textParam('parent_job', DEPLOY_DC_JOB_NAME, 'The parent job name')
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

workflowJob(CLEANUP_INFRA_JOB_NAME) {
  parameters {
    textParam('parent_job', RUN_MARVIN_TESTS_JOB_NAME, 'The parent job name')
    textParam('parent_job_build', '', 'The parent job build number')
    textParam('marvin_config_file', MARVIN_CONFIG_FILE, 'Marvin configuration file')
  }
  definition {
    cps {
      script(readFileFromWorkspace('ci/mct-workflow-cleanup-infra-job.groovy'))
    }
  }
}


