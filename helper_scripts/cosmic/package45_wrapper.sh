COSMIC_RUN_PATH=/data/git/$HOSTNAME/cosmic/cosmic-core
cd $COSMIC_RUN_PATH/packaging/centos63
./package.sh -o rhel7
cd ../../dist/rpmbuild/RPMS/x86_64
echo "Here they are:"
ls -la
