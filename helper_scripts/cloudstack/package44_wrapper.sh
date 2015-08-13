cd /data/git/$HOSTNAME/cloudstack/packaging
./package.sh -d centos7
cd ../../dist/rpmbuild/RPMS/x86_64
echo "Here they are:"
ls -la
