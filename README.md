# MCT-shared
Shared repo for our MCT CloudStack environment.

This repo is available in /data/shared on your MCT box. Feel free to add handy scripts or alter where needed.

## Testing CloudStack Pull Requests:

### Perpare management server:

This will build a VM capable of running the CloudStack management server:

```
cd /data/shared/helper_scripts/cloudstack/
./build_run_deploy_test.sh -r cloudstack-mgt-dev
```

### Perpare the infra as defined in the Marvin data center config file:

This will build the hypervisors:

```
./build_run_deploy_test.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg
```

### Run the integration tests

```
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p PRNR -b BASE_BRANCH -t
```
Example:
```
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p 1348 -b 4.7 -t
```
