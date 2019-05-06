#!/usr/bin/env python

# Wait unil templates are ready

import urllib2
import sys
import json
import time
import os.path
import getopt

class Templates():

    def __init__(self, argv):
        self.target = None
        self.handleArguments(argv)

    # Handle the arguments
    def handleArguments(self, argv):
        # Usage message
        help = "Usage: ./" + os.path.basename(__file__) + " [options]" + \
            "\n  --target -t \t\tManagement Server host (default 'localhost')"

        try:
            opts, args = getopt.getopt(
                argv, "ht:", ["target="])
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

        if self.target is None:
            self.target = "localhost"

    def list_templates(self):
        url = "http://" + self.target + ":8096/client/api?command=listTemplates&templatefilter=all&response=json"
        print url
        response = urllib2.urlopen(url)
        return response.read()

    def print_templates(self):
        templates = self.list_templates()
        print templates

    def get_json(self):
        templates = self.list_templates()
        data = json.loads(templates)['listtemplatesresponse']['template']
        return data

    def templates_ready(self):
        templates = self.get_json()
        for t in templates:
            if t is None:
                continue
            if t['isready'] != True:
                print time.strftime("%c") + " At least template '" + t['name'] + "' is not Ready"
                return False
        return True

    def wait_ready(self):
        while True:
            if self.templates_ready() == True:
                print time.strftime("%c") + " All templates are ready!"
                return True
            else:
                time.sleep(15)

t = Templates(sys.argv[1:])
print t.wait_ready()
