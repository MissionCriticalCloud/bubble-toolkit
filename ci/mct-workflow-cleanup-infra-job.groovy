import hudson.plugins.copyartifact.SpecificBuildSelector
import hudson.plugins.copyartifact.LastCompletedBuildSelector

// Job Parameters
def nodeExecutor         = executor
def parentJob            = parent_job
def parentJobBuild       = parent_job_build
def marvinConfigFile     = marvin_config_file

node(nodeExecutor) {
  copyFilesFromParentJob(parentJob, parentJobBuild, ['fresh-db-dump.sql'])

  sh  "cp /data/shared/marvin/${marvinConfigFile} ./"

  scp('root@cs1:~tomcat/vmops.log*', '.')
  scp('root@cs1:~tomcat/api.log*', '.')
  archive 'vmops.log*, api.log*'

  sh 'mkdir kvm1-agent-logs'
  scp('root@kvm1:/var/log/cloudstack/agent/agent.log*', 'kvm1-agent-logs/')
  archive 'kvm1-agent-logs/'

  sh 'mkdir kvm2-agent-logs'
  scp('root@kvm2:/var/log/cloudstack/agent/agent.log*', 'kvm2-agent-logs/')
  archive 'kvm2-agent-logs/'

  writeFile file: 'dumpDb.sh', text: 'mysqldump -u root cloud > dirty-db-dump.sql'
  scp('dumpDb.sh', 'root@cs1:./')
  ssh('root@cs1', 'chmod +x dumpDb.sh; ./dumpDb.sh')
  archive 'dirty-db-dump.sql'

  sh 'diff fresh-db-dump.sql dirty-db-dump.sql > db_diff.txt'
  archive 'db_diff.txt'

  // TODO: replace hardcoded box names
  sh '/data/vm-easy-deploy/remove_vm.sh -f cs1'
  sh '/data/vm-easy-deploy/remove_vm.sh -f kvm1'
  sh '/data/vm-easy-deploy/remove_vm.sh -f kvm2'
}

// ----------------
// Helper functions
// ----------------

// TODO: move to library
def copyFilesFromParentJob(parentJob, parentJobBuild, filesToCopy) {
  def buildSelector = { build ->
    if(build == null || build.isEmpty() || build.equals('last_completed')) {
      new LastCompletedBuildSelector()
    } else {
      new SpecificBuildSelector(build)
    }
  }

  step ([$class: 'CopyArtifact',  projectName: parentJob, selector: buildSelector(parentJobBuild), filter: filesToCopy.join(', ')]);
}

def scp(source, target) {
  sh "scp -i ~/.ssh/mccd-jenkins.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q -r ${source} ${target}"
}

def ssh(target, command) {
  sh "ssh -i ~/.ssh/mccd-jenkins.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q ${target} \"${command}\""
}

def mysqlScript(host, user, pass, db, script) {
  def passOption = pass !=  '' ? "-p${pass}" : ''
  sh "mysql -h${host} -u ${user} ${passOption} ${db} < ${script}"
}
