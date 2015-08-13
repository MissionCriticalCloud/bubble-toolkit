cd /data/git/$HOSTNAME/cloudstack/packaging/centos63
./package.sh -o rhel7
cd ../../dist/rpmbuild/RPMS/x86_64
echo "Here they are:"
ls -la
