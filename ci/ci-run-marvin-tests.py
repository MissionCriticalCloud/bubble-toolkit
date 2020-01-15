#!/usr/bin/env python

#      Copyright 2019, Schuberg Philis BV
#
#      Licensed to the Apache Software Foundation (ASF) under one
#      or more contributor license agreements.  See the NOTICE file
#      distributed with this work for additional information
#      regarding copyright ownership.  The ASF licenses this file
#      to you under the Apache License, Version 2.0 (the
#      "License"); you may not use this file except in compliance
#      with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#      Unless required by applicable law or agreed to in writing,
#      software distributed under the License is distributed on an
#      "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#      KIND, either express or implied.  See the License for the
#      specific language governing permissions and limitations
#      under the License.

#      Script to deploy infrastructure
#      Written by Alexander Verhaar, Schuberg Philis
#      sanderv32@gmail.com

from __future__ import print_function

import click
from Cosmic.CI import CI


@click.command()
@click.option('--marvin-config', '-m', help='Marvin config file', required=True)
@click.option('--debug', help="Turn on debugging output", is_flag=True)
@click.argument('tests', nargs=-1, required=True)
def main(**kwargs):
    ci = CI(marvin_config=kwargs.get('marvin_config'), debug=kwargs.get('debug'))
    ci.marvin_tests(kwargs.get('tests'))
    print("==> ")
    ci.add_nsx_connectivy_to_offerings()


if __name__ == '__main__':
    main()
