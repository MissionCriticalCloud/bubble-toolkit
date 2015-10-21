import hudson.model.StringParameterValue
import com.cloudbees.plugins.credentials.CredentialsParameterValue
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.common.StandardUsernameCredentials

def mctCheckoutParameters = [
  new StringParameterValue('git_repo_url', 'https://github.com/schubergphilis/MCCloud', 'Git repository URL'),
  new StringParameterValue('sha1', 'tmp/combined-prs-496-497-498', 'Git branch'),
  new CredentialsParameterValue('git_repo_credentials', '298a5b23-7bfc-4b68-82aa-ca44465b157d', 'Git repo credentials')
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
  new StringParameterValue('hypervisor_hosts', 'kvm1 kvm2', 'Hypervisor Hosts'),
  new StringParameterValue('secondary_storage_location', '/data/storage/secondary/MCCT-SHARED-1', 'Secondary Storage Location'),
  new StringParameterValue('marvin_config_file', 'mct-zone1-kvm1-kvm2.cfg', 'Marvin Configuration File')
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
  new StringParameterValue('marvin_config_file', 'mct-zone1-kvm1-kvm2.cfg', 'Marvin Configuration File')
]

def deployDcJobBuild = build job: 'mccloud/mct-deploy-data-center', parameters: mctDeployDcParameters

print "==> Deploy DC Job Id       = ${deployDcJobBuild.getId()}"
print "==> Deploy DC Job Name     = ${deployDcJobBuild.getName()}"
print "==> Deploy DC Build Number = ${deployDcJobBuild.getNumber()}"

def deployDcJobName        = deployDcJobBuild.getName()
def deployDcJobBuildNumber = deployDcJobBuild.getNumber()

def marvinTestsWithHw = [
  'component/test_vpc_redundant',
  'component/test_routers_iptables_default_policy',
  'component/test_routers_network_ops',
  'component/test_vpc_router_nics',
  'smoke/test_loadbalance'
]

def marvinTestsWithoutHw = [
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

def mctRunMarvinTestsParameters = [
  new StringParameterValue('parent_job', deployDcJobName, 'Parent Job Name'),
  new StringParameterValue('parent_job_build', deployDcJobBuildNumber, 'Parent Job Build Number'),
  new StringParameterValue('marvin_tests_with_hw', marvinTestsWithHw.join(' '), 'Marvin tests that require Hardware'),
  new StringParameterValue('marvin_tests_without_hw', marvinTestsWithoutHw.join(' '), 'Marvin tests that do not require Hardware'),
  new StringParameterValue('marvin_config_file', 'mct-zone1-kvm1-kvm2.cfg', 'Marvin Configuration File')
]

def runMarvinTestsJobBuild = build job: 'mccloud/mct-run-marvin-tests', parameters: mctRunMarvinTestsParameters

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
