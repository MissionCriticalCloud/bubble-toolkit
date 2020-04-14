#!/usr/bin/env python
import sys

import click
from Cosmic.CI import CI
from Cosmic.NSX import NSX


@click.command()
@click.option('--marvin-config', '-m', help='Marvin config file', required=True)
@click.option('--cloudstack', '-c', help='Cloudstack deploy mode', default=False, is_flag=True, required=False)
@click.option('--debug', help="Turn on debugging output", is_flag=True)
@click.option('--template', help='Use template', required=False)
def main(**kwargs):
    isolation_mode = "vxlan"
    cloudstack_deploy_mode = kwargs.get('cloudstack')
    template = kwargs.get('template') or '/data/templates/cosmic-systemvm.qcow2'
    ci = CI(marvin_config=kwargs.get('marvin_config'), debug=kwargs.get('debug'))

    ci.deploy_cosmic_db()
    ci.install_systemvm_templates(template=template)

    nsx = NSX(marvin_config=kwargs.get('marvin_config'), debug=kwargs.get('debug'))
    if nsx:
        nsx.create_cluster()

    ci.configure_tomcat_to_load_jacoco_agent()
    ci.deploy_cosmic_war()
    ci.install_kvm_packages()
    ci.configure_agent_to_load_jacoco_agent()

    if nsx:
        nsx.configure_kvm_host()

    if nsx:
        if cloudstack_deploy_mode:
            isolation_mode = "stt"
        nsx.setup_cosmic(isolation_mode=isolation_mode)


if __name__ == '__main__':
    sys.exit(main())
