#!/usr/bin/python

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

    def list_templates(self):
        url = "http://" + self.target + ":8096/client/api?command=listTemplates&templatefilter=all&response=json"
        print "Connecting to url %s" % url
        try:
            response = urllib2.urlopen(url)
            return response.read()
        except:
            print "Problem connecting to %s" % url
            return False

    def print_templates(self):
        templates = self.list_templates()
        if templates:
            print templates

    def get_json(self):
        templates = self.list_templates()
        try:
            data = json.loads(templates)['listtemplatesresponse']['template']
            return data
        except:
            return False

    def templates_ready(self):
        templates = self.get_json()
        if not templates:
            return False
        for t in templates:
            if t is None:
                continue
            if t['isready'] != True:
                print time.strftime("%c") + " At least template '" + t['name'] + "' is not ready, trying again soon.."
                return False
        return True

    def wait_ready(self):
        tries = 1
        print "Attempt %s/%s" % (tries, self.retries)
        while True:
            if self.templates_ready():
                print time.strftime("%c") + " All templates are ready!"
                return True

            tries += 1
            if tries > int(self.retries):
                print "ERROR: After %s retries still no ready templates. Aborting." % self.retries
                sys.exit(1)

            print "Sleeping 15s.."
            time.sleep(15)

t = Templates(sys.argv[1:])
print t.wait_ready()
