# Bubble Toolkit
Shared toolkit repository to be used with Bubbles.

This repo is available in /data/shared on your Bubble. Feel free to add handy scripts or alter where needed.

## Testing CloudStack or Cosmic Pull Requests:

### Perpare management server:

This will build a VM capable of running the management server:

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
ssh cs1
cd /data/shared/helper_script/cloudstack
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p PRNR -b BASE_BRANCH -t
```
Example:
```
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p 1348 -b 4.8 -t
```

If you want to run your own tests, you can specify the `-f test_file_name.sh` flag.  
If you don't specify a test file with the `-f` flag, it will automatically default to the following test scenario:
```
 ./check-pr.sh -m /data/shared/marvin/mct-zone1-kvm1-kvm2.cfg -p 1348 -b 4.8 -t -f run_marvin_router_tests.sh
```
This will run the tests defined in the `/data/share/helper_scripts/cloudstack/run_marvin_router_tests.sh` file.

### Results of a test:

![screen shot 2016-01-20 at 11 29 42](https://cloud.githubusercontent.com/assets/1630096/12446309/9433e286-bf69-11e5-8906-77bfeca86dea.png)

### Testing to the Maxxx

![screen shot 2015-10-23 at 16 47 08](https://cloud.githubusercontent.com/assets/1630096/12446386/f5b2548e-bf69-11e5-936d-94eedf41b548.png)

License and Authors
-------------------
Authors:
* Fred Neubauer
* Remi Bergsma
* Bob van den Heuvel
* Boris Schrijver
* Miguel Ferreira
* Wilder Rodrigues

```text
Copyright 2016, Schuberg Philis

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
