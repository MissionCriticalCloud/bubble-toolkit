#
#

import urllib
import os
import sys
import xml.dom.minidom
import re
import base64
import hmac
import hashlib
import httplib
import time
import marvin
import json
import urllib
import urllib2
import logging

from marvin.cloudstackConnection import CSConnection
from marvin.cloudstackException import CloudstackAPIException
from marvin.cloudstackAPI import *
from marvin import cloudstackAPI

class CSUtils(object):

   def getApiKeys(self, host, username, password, domain):
     if domain == None :
       loginparams = urllib.urlencode({'username': username, 'password': password, 'command': 'login'})
     else:
       loginparams = urllib.urlencode({'username': username, 'password': password, 'domain': domain, 'command': 'login'})
     headers = {"Content-type": "application/x-www-form-urlencoded", "Accept": "text/plain"}
     connection = httplib.HTTPConnection(host, 8080)
     request = connection.request("POST", "/client/api?login", loginparams, headers);
     resp = connection.getresponse()
     cookies = resp.getheader('Set-cookie')
     matchObj = re.match( r'JSESSIONID=(.*);.*', cookies, re.M|re.I)
     sessionId = matchObj.group(1);

     dom = xml.dom.minidom.parseString(resp.read())
     if len(dom.getElementsByTagName('sessionkey')) == 0:
         print "Login failed"
         sys.exit(-1)

     sessionKey = dom.getElementsByTagName('sessionkey')[0].firstChild.data
   #  userId = dom.getElementsByTagName('userid')[0].firstChild.data
     userId = 2

     print "# Connected with user %s (%s) with sessionKey %s" % (username, userId, sessionKey)

     params = urllib.urlencode({'command':'listUsers', 'id':userId, 'sessionkey':sessionKey})
     headers = {"Cookie" : "JSESSIONID=%s" % sessionId}
     request = connection.request("GET", "/client/api?%s" % params, None, headers);
     resp = connection.getresponse()
     dom = xml.dom.minidom.parseString(resp.read())
     if dom.getElementsByTagName('apikey') :
       apiKey = dom.getElementsByTagName('apikey')[0].firstChild.data
       secretKey = dom.getElementsByTagName('secretkey')[0].firstChild.data
     else:
       print "# Account has no apikey, executing registerUserKeys"
       params = urllib.urlencode({'command':'registerUserKeys', 'id':userId, 'sessionkey':sessionKey})
       headers = {"Cookie" : "JSESSIONID=%s" % sessionId}
       request = connection.request("GET", "/client/api?%s" % params, None, headers);
       resp = connection.getresponse()
       dom = xml.dom.minidom.parseString(resp.read())
       apiKey = dom.getElementsByTagName('apikey')[0].firstChild.data
       secretKey = dom.getElementsByTagName('secretkey')[0].firstChild.data

     connection.close()
     return (apiKey, secretKey)

   def getConnection(self):
      (apikey, secretkey) = self.getApiKeys("localhost", "admin", "password", None)
      blub = mgmtDetails()
      blub.apiKey=apikey
      blub.securityKey=secretkey

      conn = CSConnection(blub, logger=logging)
      return conn


class mgmtDetails(object):
    apiKey = ""
    securityKey = ""
    mgtSvrIp = "localhost"
    port = 8080
    user = "admin"
    passwd = "password"
    certCAPath = None
    certPath = None
    useHttps = "False"

