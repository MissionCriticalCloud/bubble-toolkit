from __future__ import print_function
import glob
import os
import json
import socket
import time

import cs
import paramiko
import scp


class Base(object):
    """Initializes Base class with the given ``marvin_config`` file

    :param marvin_config: Path to marvin file
    :param debug: Output debug information
    """
    def __init__(self, marvin_config=None, debug=False):
        if marvin_config is None:
            raise Exception("No Marvin config supplied")
        print("==> Received arguments:\n"
              "==> marvin_config = {0}\n"
              "==> Using Marvin config '{0}'\n".format(marvin_config))
        if not os.path.exists(marvin_config):
            raise Exception("Supplied Marvin config not found!")
        self.config = json.loads(open(marvin_config).read())
        self.marvin_config = marvin_config
        self.debug = debug
        self.ssh_client = paramiko.SSHClient()
        self.ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    def _ssh(self, hostname=None, username=None, password=None, cmd=None):
        """Connect to hostname via SSH

        :param hostname: Hostname/IP to connect to
        :param username: Username
        :param password: Password
        :param cmd: Command to execute
        :return: A tuple with exitcode, stdout, stderr
        """
        self.ssh_client.connect(hostname=hostname,
                                username=username,
                                password=password)

        _stdin, _stdout, _stderr = self.ssh_client.exec_command(command=cmd, timeout=60)
        exitcode = _stdout.channel.recv_exit_status()
        _stderr_buffer = _stderr.readlines()
        _stdout_buffer = _stdout.readlines()

        if self.debug:
            print("==> command: %s\n"
                  "==> exitcode: %s\n"
                  "==> stdout: %s\n"
                  "==> stderr: %s\n" % (cmd, exitcode, _stderr_buffer, _stdout_buffer))
        return exitcode, _stdout_buffer, _stderr_buffer

    def _scp_get(self, hostname=None, username=None, password=None, srcfile=None, destfile=None):
        """SCP Get file

        :param hostname: FQDN/IP
        :param username: Username
        :param password: Password
        :param srcfile: Source file
        :param destfile: Destination file
        """
        self.ssh_client.connect(hostname=hostname,
                                username=username,
                                password=password)
        scp_client = scp.SCPClient(self.ssh_client.get_transport())
        scp_client.get(srcfile, destfile, recursive=True)
        scp_client.close()

    def _scp_put(self, hostname=None, username=None, password=None, srcfile=None, destfile=None):
        """SCP Put file

        :param hostname: FQDN/IP
        :param username: Username
        :param password: Password
        :param srcfile: Source file
        :param destfile: Destination file
        """
        self.ssh_client.connect(hostname=hostname,
                                username=username,
                                password=password)
        scp_client = scp.SCPClient(self.ssh_client.get_transport())
        if '*' in srcfile:
            listing = glob.glob(srcfile)
            if len(listing) == 0:
                raise Exception("No file found: " + srcfile)
            srcfile = listing
        scp_client.put(srcfile, destfile, recursive=True)
        scp_client.close()

    def wait_for_port(self, hostname=None, tcp_port=8096):
        """Wait for port to be ready

        :param hostname: Hostname to connect to
        :param tcp_port: Port number to connect to
        """
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        while True:
            try:
                s.connect((hostname, tcp_port))
                s.close()
                break
            except socket.error as _:
                if self.debug:
                    print("==> %s not ready" % hostname)
                time.sleep(1)

    def wait_for_templates(self, retries=99):
        """Wait for templates to become ready

        :param retries: Number of retries
        """
        for mgtSvr in self.config['mgtSvr']:
            self.wait_for_port(hostname=mgtSvr['mgtSvrIp'])
            cosmic = cs.CloudStack(endpoint="http://" + mgtSvr['mgtSvrIp'] + ":" + str(mgtSvr['port']),
                                   key='', secret='', verify=False)

            templates = cosmic.listTemplates(templatefilter='all')
            for template in templates['template']:
                if template['isready']:
                    continue
                ready = False
                retry = 0
                while not ready:
                    tmpl = cosmic.listTemplates(id=template['id'], templatefilter='all')
                    if tmpl['template'][0]['isready']:
                        ready = True
                    if retry == retries:
                        break
                    retry += 1
                    print("==> Template '%s' on '%s' not ready, waiting 10s [retry %i/%i]" %
                          (tmpl['template'][0]['name'], mgtSvr['mgtSvrName'], retry, retries))
                    time.sleep(10)
                if retry == retries and not ready:
                    print("==> Template '%s' on '%s' not ready!" % (template['name'], mgtSvr['mgtSvrName']))
