#!/usr/bin/env python

# Wait unil templates are ready

import urllib2
import sys
import json
import time
import os.path
import getopt


class Templates:

    def __init__(self, argv):
        self.target = None
        self.retries = 100
        self.handle_arguments(argv)

    # Handle the arguments
    def handle_arguments(self, argv):
        # Usage message
        help = "Usage: ./" + os.path.basename(__file__) + " [options]" + \
            "\n  --target -t \t\tManagement Server host (default 'localhost')" + \
            "\n  --retries -r \t\tNumber of retries (default 100)"

        try:
            opts, args = getopt.getopt(
                argv, "ht:r:", ["target=", "retries="])
        except getopt.GetoptError as e:
            print "Error: " + str(e)
            print help
            sys.exit(2)

        for opt, arg in opts:
            print "processing option " + opt + " arg " + arg
            if opt == "-h":
                print help
                sys.exit()
            elif opt in ("-t", "--target"):
                self.target = arg
            elif opt in ("-r", "--retries"):
                self.retries = arg

        if self.target is None:
            self.target = "localhost"

    def send_api_cmd(self, cmd):
        url = "http://" + self.target + ":8096/client/api?command=%s" % cmd
        print "Calling %s" % url
        try:
            response = urllib2.urlopen(url)
            return response.read()
        except:
            print time.strftime("%c") + " Problem connecting to %s" % url
            return False

    def list_templates(self):
        cmd = "listTemplates&templatefilter=all&response=json"
        return self.send_api_cmd(cmd)

    def list_systemvms(self):
        cmd = "listSystemVms&response=json"
        return self.send_api_cmd(cmd)

    def start_systemvm(self, id):
        cmd = "startSystemVm&response=json&id=%s" % id
        return self.send_api_cmd(cmd)

    def print_templates(self):
        templates = self.list_templates()
        if templates:
            print templates

    def get_json(self, fieldname):
        if fieldname == "template":
            jsondata = self.list_templates()
        if fieldname == 'systemvm':
            jsondata = self.list_systemvms()
        try:
            data = json.loads(jsondata)
            return data[data.keys()[0]][fieldname]
        except:
            return False

    def templates_ready(self):
        templates = self.get_json('template')
        if not templates:
            return False
        for t in templates:
            if t is None:
                continue
            if t['isready'] != True:
                print time.strftime("%c") + " At least template '%s' is not ready, trying again soon.." % t['name']
                return False
        return True

    def systemvms_ready(self):
        systemvms = self.get_json('systemvm')
        if not systemvms:
            return False
        for s in systemvms:
            if s is None:
                continue

            if s['state'] == 'Stopped':
                print time.strftime("%c") + " Found a stopped systemvm with uuid %s, starting it..." % s['id']
                self.start_systemvm(s['id'])

            if s['state'] != 'Running':
                print time.strftime("%c") + " Found systemvm %s in state %s so not ready, trying again soon.." \
                                            % (s['name'], s['state'])
                return False
        return True

    def wait_ready(self):
        tries = 1
        while True:
            if tries > int(self.retries):
                print "ERROR: After %s retries still no ready templates. Aborting." % self.retries
                sys.exit(1)
            if tries > 1:
                print "Sleeping 15s.."
                time.sleep(15)
            print "Attempt %s/%s" % (tries, self.retries)
            tries += 1

            if self.systemvms_ready():
                print time.strftime("%c") + " All systemvms are Running, good!"
            else:
                print time.strftime("%c") + " Systemvms are not yet ready, waiting.."
                continue

            if self.templates_ready():
                print time.strftime("%c") + " All templates are ready!"
                return True
            else:
                print time.strftime("%c") + " Not all templates are ready yet!"

t = Templates(sys.argv[1:])
print t.wait_ready()
