#! /bin/bash

set -e

cd packaging
./package.sh -d centos7
cd ..
cp dist/rpmbuild/RPMS/x86_64/cloudstack-agent-*.rpm .
cp dist/rpmbuild/RPMS/x86_64/cloudstack-common-*.rpm .
rm -rf dist
