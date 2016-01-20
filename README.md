# MCT-shared
Shared repo for our MCT CloudStack environment.

This repo is available in /data/shared on your MCT box. Feel free to add handy scripts or alter where needed.

## Testing CloudStack Pull Requests:

### Perpare management server:

This will build a VM capable of running the CloudStack management server:

```
cd /data/shared/deploy/
./kvm_local_deploy.py -r cloudstack-mgt-dev
```

### Perpare the infra as defined in the Marvin data center config file:

This will build the hypervisors:

```
./kvm_local_deploy.py -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg
```

### Run the integration tests

```
cd /data/shared/helper_script/cloudstack
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p PRNR -b BASE_BRANCH -t
```
Example:
```
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p 1348 -b 4.7 -t
```

### Results of a test:

![screen shot 2016-01-20 at 11 29 42](https://cloud.githubusercontent.com/assets/1630096/12446309/9433e286-bf69-11e5-8906-77bfeca86dea.png)

### Testing to the Maxxx

![screen shot 2015-10-23 at 16 47 08](https://cloud.githubusercontent.com/assets/1630096/12446386/f5b2548e-bf69-11e5-936d-94eedf41b548.png)
