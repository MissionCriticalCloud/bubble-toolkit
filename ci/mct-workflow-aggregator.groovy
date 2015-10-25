import jenkins.model.Jenkins
import hudson.model.StringParameterValue
import com.cloudbees.plugins.credentials.CredentialsParameterValue
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.common.StandardUsernameCredentials

// Job Parameters
def gitRepoUrl           = git_repo_url
def gitBranch            = sha1
def gitRepoCredentials   = git_repo_credentials
def marvinTestsWithHw    = (marvin_tests_with_hw.split(' ') as List)
def marvinTestsWithoutHw = (marvin_tests_without_hw.split(' ') as List)
def marvinConfigFile     = marvin_config_file

def mctCheckoutParameters = [
  new StringParameterValue('git_repo_url', gitRepoUrl, 'Git repository URL'),
  new StringParameterValue('sha1', gitBranch, 'Git branch'),
  new CredentialsParameterValue('git_repo_credentials', gitRepoCredentials, 'Git repo credentials')
]

def checkoutJobName  = './mct-checkout'
def checkoutJobBuild = build job: checkoutJobName, parameters: mctCheckoutParameters

def checkoutJobBuildNumber = checkoutJobBuild.getNumber() as String
print "==> Chekout Build Number = ${checkoutJobBuildNumber}"

// NOTE: This only works if we set a quiet period for the job, otherwise two jobs might be scheduled too fast
// and the same executoer might be picked for both.
def executor = getAvailableNode('executor-mct')
print "==> Elected MCT executor ${executor} for this build"

def mctDeployInfraParameters =[
  new StringParameterValue('executor', executor, 'Executor'),
  new StringParameterValue('parent_job', checkoutJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', checkoutJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

def deployInfraJobName  = './mct-deploy-infra'
def deployInfraJobBuild = build job: deployInfraJobName, parameters: mctDeployInfraParameters

def deployInfraJobBuildNumber = deployInfraJobBuild.getNumber() as String
print "==> Deploy Infra Build Number = ${deployInfraJobBuildNumber}"

def mctDeployDcParameters =[
  new StringParameterValue('executor', executor, 'Executor'),
  new StringParameterValue('parent_job', checkoutJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', checkoutJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

def deployDcJobName  = './mct-deploy-data-center'
def deployDcJobBuild = build job: deployDcJobName, parameters: mctDeployDcParameters

def deployDcJobBuildNumber = deployDcJobBuild.getNumber() as String
print "==> Deploy DC Build Number = ${deployDcJobBuildNumber}"

def mctRunMarvinTestsParameters = [
  new StringParameterValue('executor', executor, 'Executor'),
  new StringParameterValue('parent_job', checkoutJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', checkoutJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_tests_with_hw', marvinTestsWithHw.join(' '), 'Marvin tests that require Hardware'),
  new StringParameterValue('marvin_tests_without_hw', marvinTestsWithoutHw.join(' '), 'Marvin tests that do not require Hardware'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

try {
  def runMarvinTestsJobName  = './mct-run-marvin-tests'
  def runMarvinTestsJobBuild = build job: runMarvinTestsJobName, parameters: mctRunMarvinTestsParameters
}
catch(e) {
  echo "==> Marvin tests build was not successful"
}
finally {
  def runMarvinTestsJobBuildNumber = runMarvinTestsJobBuild.getNumber() as String
  print "==> Run Marvin Tests Build Number = ${runMarvinTestsJobBuildNumber}"

  def mctCleanUpInfraParameters = [
    new StringParameterValue('executor', executor, 'Executor'),
    new StringParameterValue('parent_job', deployDcJobName, 'Parent Job Name'),
    new StringParameterValue('parent_job_build', deployDcJobBuildNumber, 'Parent Job Build Number'),
    new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
  ]

  def cleanUpInfraJobBuild = build job: './mct-cleanup-infra', parameters: mctCleanUpInfraParameters

  print "==> Clean Up Infra Build Number = ${cleanUpInfraJobBuild.getNumber()}"
}




//def credentials = findCredentials({ c -> c.id  == '298a5b23-7bfc-4b68-82aa-ca44465b157d' })
def findCredentials(matcher) {
  def creds = CredentialsProvider.lookupCredentials(StandardUsernameCredentials.class)
  for (c in creds) {
      if(matcher(c)) {
        return c
      }
  }
  return null
}

def getAvailableNodes(label) {
  def nodeNames = []
  Jenkins.instance.nodes.each { n ->
    def labels = n.getLabelString().split('\\s+')
    if(labels.contains(label) && n.getComputer().countBusy() == 0) {
      nodeNames += n.getNodeName()
    }
  }
  nodeNames
}

def getAvailableNode(label) {
  def nodes = getAvailableNodes(label)
  if(nodes.size() < 1) {
    throw new Exception('Can\'t find an available \'executor-mct\' node')
  }
  nodes.getAt(0)
}
