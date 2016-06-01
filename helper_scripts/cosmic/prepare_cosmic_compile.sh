#!/bin/bash
. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/helperlib.sh
# Script to prepare source for Cosmic compile

# Get source
BASEDIR=/data/git/${HOSTNAME}
GITSSH=1

while getopts 'h' OPTION
do
  case $OPTION in
  h)    GITSSH=0
        ;;
  esac
done

cosmic_sources_retrieve ${BASEDIR} ${GITSSH}

# Set MVN compile options
export MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=512m -Xdebug -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=n -Djava.net.preferIPv4Stack=true"
echo "Done."
