// Job Parameters
def gitRepoUrl           = git_repo_url
def gitRepoCredentials   = git_repo_credentials
def gitBranch            = sha1

// Job constants

// TODO: move to library
def DB_SCRIPTS = [
  'setup/db/db/',
  'setup/db/create-*.sql',
  'setup/db/templates*.sql',
  'developer/developer-prefill.sql'
]

// TODO: move to library
def TEMPLATE_SCRIPTS = [
  'scripts/storage/secondary/'
]

// TODO: move to library
def MARVIN_SCRIPTS = [
  'test/integration/',
  'tools/travis/xunit-reader.py'
]

node('executor') {
  checkout scm: [$class: 'GitSCM', branches:          [[name: gitBranch]],
                                   userRemoteConfigs: [[url:  gitRepoUrl, credentialsId: gitRepoCredentials]]]

  def projectVersion = version()

  mvn 'clean install -Pdeveloper,systemvm -T 4'
  step([$class: 'JUnitResultArchiver', testResults: '**/target/surefire-reports/*.xml'])

  packageRpm('centos7')

  archive "client/target/cloud-client-ui-${projectVersion}.war"
  archive "dist/rpmbuild/RPMS/x86_64/cloudstack-agent-${projectVersion}*.rpm"
  archive "dist/rpmbuild/RPMS/x86_64/cloudstack-common-${projectVersion}*.rpm"
  archive "tools/marvin/dist/Marvin-${projectVersion}.tar.gz"
  archive DB_SCRIPTS.join(', ')
  archive TEMPLATE_SCRIPTS.join(', ')
  archive MARVIN_SCRIPTS.join(', ')
}

// ----------------
// Helper functions
// ----------------


def packageRpm(distribution) {
  dir('packaging') {
    sh "./package.sh -d ${distribution}"
  }
}

def mvn(args) {
  sh "${tool 'M3'}/bin/mvn ${args}"
}

def version() {
  def matcher = readFile('pom.xml') =~ '<version>(.+)</version>'
  // first matche will be parent version, so we take the seccond ie, matcher[1]
  matcher ? matcher[1][1] : null
}
