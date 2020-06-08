#!/usr/bin/env python

import click
from Cosmic.CI import *
from Cosmic.NSX import *


@click.command()
@click.option('--marvin-config', '-m', help='Marvin config file', required=True)
@click.option('--debug', help="Turn on debugging output", is_flag=True)
def main(**kwargs):
    ci = CI(marvin_config=kwargs.get('marvin_config'), debug=kwargs.get('debug'))
    nsx = NSX(marvin_config=kwargs.get('marvin_config'), debug=kwargs.get('debug'))
    ci.wait_for_port(ci.config['mgtSvr'][0]['mgtSvrIp'])
    ci.copy_marvin_config()
    ci.deploy_dc()

    if nsx is not None:
        print("Setting connectivity for NSX offerings")
        nsx.add_connectivy_to_offerings()

    ci.wait_for_templates()


if __name__ == '__main__':
    main()
