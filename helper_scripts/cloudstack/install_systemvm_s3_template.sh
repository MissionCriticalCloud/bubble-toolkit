#!/bin/bash

# Use the s3 template at: mcct-nl1.s3.storage.acc.schubergphilis.com
# For now it's a KVM systemvm template.

templateId=$(mysql -P 3306 -h localhost --user=root --password= --skip-column-names -U cloud -e 'select max(id) from cloud.vm_template where type = "SYSTEM" and hypervisor_type = "KVM" and removed is null')

mysql -P 3306 -h localhost --user=root --password= --skip-column-names -U cloud -e 'update cloud.vm_template set uuid="11f3b47b-78ba-4469-8f7d-c85e205b452c", url="" where id="${templateId}"'
