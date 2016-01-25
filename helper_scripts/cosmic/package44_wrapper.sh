COSMIC_RUN_PATH=/data/git/$HOSTNAME/cosmic/cosmic-core
cd $COSMIC_RUN_PATH/packaging
./package.sh -d centos7
cd $COSMIC_RUN_PATH/dist/rpmbuild/RPMS/x86_64
echo "Here they are:"
ls -la
