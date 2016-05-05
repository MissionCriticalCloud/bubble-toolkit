#!/usr/bin/env python
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

## --- DISCLAIMER ---
## This script is full of !!! MAGIC !!!, so if you have a problem with that
## you are welcome to implement your own solution to this problem.  :)

from os import listdir
from os.path import isdir, isfile, join
import sys

if __name__ == '__main__':
    root_dir = '/tmp/MarvinLogs/'
    if len(sys.argv) > 1:
        root_dir = sys.argv[1] # override the default root dir if a path is specified
    # only look for results.txt files in directories that could be tests.
    # this is usually directories that start with 'test_', but if exceptions occur they can just be a 6 char hash.
    test_dirs = ["%s%s" % (root_dir, d) for d in listdir(root_dir) if isdir(join(root_dir, d)) and not d.startswith("DeployDataCenter")]

    tests_run = 0
    run_details = {}
    fail_details = []
    tests_run_parse_error = False
    tests_time = 0
    for directory in test_dirs:
        if isfile(join(directory, "results.txt")): # we have a results.txt file to process
            file_details = [] # add the fail_details to this temp array so we can fix the order later
            with open(join(directory, "results.txt")) as f:
                capturing = False
                captured = """""" # multiline string so we don't have to worry about escaping quotes etc
                for i, line in enumerate(reversed(f.readlines())): # go through the lines backwards to simplify getting last lines
                    
                    if i == 0 and line[0:6] == 'FAILED': # capture failures
                        run_detail = line[8:-2] # get the section of the line that will describe the failures
                        run_detail = '{"%s}' % (run_detail) # do some magic to turn the string into a dict
                        run_detail = run_detail.replace(', ', ', "').replace('=', '":')
                        run_detail = eval(run_detail) # now that we have formatted the string, turn it into a dict
                        for k, v in run_detail.items():
                            if k in run_details:
                                run_details[k] += v
                            else:
                                run_details[k] = v

                    if i == 0 and line[0:4] == 'OK (': # capture skips on their own
                        run_detail = line[4:-2] # get the section of the line that will describe the skips
                        run_detail = '{"%s}' % (run_detail) # do some magic to turn the string into a dict
                        run_detail = run_detail.replace(', ', ', "').replace('=', '":')
                        run_detail = eval(run_detail) # now that we have formatted the string, turn it into a dict
                        for k, v in run_detail.items():
                            if k in run_details:
                                run_details[k] += v
                            else:
                                run_details[k] = v

                    if i == 2: # collect the number of tests run
                        if line[0:4] == 'Ran ':
                            s_parts = line.split(' ') # split on spaces
                            tests_run += int(s_parts[1]) # second item is the number of tests run
                            tests_time += float(s_parts[-1][:-2]) # grab the last item in the list and remove the 's ' from the end
                        else:
                            tests_run_parse_error = True

                    if line.startswith('-------------------- >> begin captured logging << --------------------'):
                        capturing = True
                        captured = """----------------------------------------------------------------------
Additional details in: %s""" % join(directory, "results.txt")
                        continue # skip this line in the output
                    if line.startswith('======================================================================'):
                        capturing = False
                        file_details.append(captured)
                        captured = """"""
                        continue # move on to the next line

                    if capturing:
                        captured = """%s%s""" % (line, captured)
            fail_details += reversed(file_details) # so the order of 'fail_details' matches execution order

    # print the output to the screen so it can be piped into 'upr'
    print('### CI RESULTS\n')
    print('```')
    print('Tests Run: %s%s' % (tests_run, ('*' if tests_run_parse_error else '')))
    print('  Skipped: %s' % (run_details['SKIP'] if 'SKIP' in run_details else 0))
    print('   Failed: %s' % (run_details['failures'] if 'failures' in run_details else 0))
    print('   Errors: %s' % (run_details['errors'] if 'errors' in run_details else 0))
    if tests_time > 0:
        m, s = divmod(tests_time, 60)
        h, m = divmod(m, 60)
        print " Duration: %dh %02dm %02ds" % (h, m, s)
    if tests_run_parse_error:
        print('\n* The `Tests Run` value is likely incorrect due to exceptions')
    print('```\n')
    if len(fail_details) > 0:
        print('**Summary of the problem(s):**')
    for entry in fail_details:
        print('```')
        print(entry)
        print('```')
        print('')

