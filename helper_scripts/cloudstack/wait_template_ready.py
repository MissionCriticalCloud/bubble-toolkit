#!/usr/bin/python

# Wait unil templates are ready

import urllib2
import sys
import json
import time

class Templates():

    def list_templates(self):
        url = "http://localhost:8096/client/api?command=listTemplates&templatefilter=all&response=json"
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

t = Templates()
print t.wait_ready()
