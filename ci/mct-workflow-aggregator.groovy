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

def checkoutJobBuild = build job: 'mccloud/mct-checkout', parameters: mctCheckoutParameters

print "==> Chekout Job Id       = ${checkoutJobBuild.getId()}"
print "==> Chekout Job Name     = ${checkoutJobBuild.getName()}"
print "==> Chekout Build Number = ${checkoutJobBuild.getNumber()}"

def checkoutJobName        = checkoutJobBuild.getName()
def checkoutJobBuildNumber = checkoutJobBuild.getNumber()

def mctDeployInfraParameters =[
  new StringParameterValue('parent_job', checkoutJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', checkoutJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

def deployInfraJobBuild = build job: 'mccloud/mct-deploy-infra', parameters: mctDeployInfraParameters

print "==> Deploy Infra Job Id       = ${deployInfraJobBuild.getId()}"
print "==> Deploy Infra Job Name     = ${deployInfraJobBuild.getName()}"
print "==> Deploy Infra Build Number = ${deployInfraJobBuild.getNumber()}"

def deployInfraJobName        = deployInfraJobBuild.getName()
def deployInfraJobBuildNumber = deployInfraJobBuild.getNumber()

def mctDeployDcParameters =[
  new StringParameterValue('parent_job', deployInfraJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', deployInfraJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

def deployDcJobBuild = build job: 'mccloud/mct-deploy-data-center', parameters: mctDeployDcParameters

print "==> Deploy DC Job Id       = ${deployDcJobBuild.getId()}"
print "==> Deploy DC Job Name     = ${deployDcJobBuild.getName()}"
print "==> Deploy DC Build Number = ${deployDcJobBuild.getNumber()}"

def deployDcJobName        = deployDcJobBuild.getName()
def deployDcJobBuildNumber = deployDcJobBuild.getNumber()

def mctRunMarvinTestsParameters = [
  new StringParameterValue('parent_job', deployDcJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', deployDcJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_tests_with_hw', marvinTestsWithHw.join(' '), 'Marvin tests that require Hardware'),
  new StringParameterValue('marvin_tests_without_hw', marvinTestsWithoutHw.join(' '), 'Marvin tests that do not require Hardware'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

def runMarvinTestsJobBuild = build job: 'mccloud/mct-run-marvin-tests', parameters: mctRunMarvinTestsParameters

print "==> Run Marvin Tests Job Id       = ${runMarvinTestsJobBuild.getId()}"
print "==> Run Marvin Tests Job Name     = ${runMarvinTestsJobBuild.getName()}"
print "==> Run Marvin Tests Build Number = ${runMarvinTestsJobBuild.getNumber()}"

def runMarvinTestsJobName        = runMarvinTestsJobBuild.getName()
def runMarvinTestsJobBuildNumber = runMarvinTestsJobBuild.getNumber()

def mctCleanUpInfraParameters = [
  new StringParameterValue('parent_job', runMarvinTestsJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', runMarvinTestsJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_config_file', marvinConfigFile, 'Marvin Configuration File')
]

def cleanUpInfraJobBuild = build job: 'mccloud/mct-cleanup-infra', parameters: mctCleanUpInfraParameters

print "==> Clean Up Infra Job Id       = ${cleanUpInfraJobBuild.getId()}"
print "==> Clean Up Infra Job Name     = ${cleanUpInfraJobBuild.getName()}"
print "==> Clean Up Infra Build Number = ${cleanUpInfraJobBuild.getNumber()}"

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
