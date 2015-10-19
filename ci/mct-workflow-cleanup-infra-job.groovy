import hudson.plugins.copyartifact.SpecificBuildSelector

// Job Parameters
def parentJob            = parent_job
def parentJobBuild       = parent_job_build
def marvinConfigFile     = marvin_config_file

node('executor-mct') {
  copyFilesFromParentJob(parentJob, parentJobBuild, [marvinConfigFile])

  scp('root@cs1:~tomcat/vmops.log', '.')
  scp('root@cs1:~tomcat/api.log', '.')
  archive 'vmops.log, api.log'
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
  step ([$class: 'CopyArtifact',  projectName: parentJob,  selector: new SpecificBuildSelector(parentJobBuild), filter: filesToCopy.join(', ')]);
}

def scp(source, target) {
  sh "scp -i ~/.ssh/mccd-jenkins.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q -r ${source} ${target}"
}
