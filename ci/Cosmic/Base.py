from __future__ import print_function
import glob
import os
import json
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
        self.ssh_client.connect(hostname=hostname,
                                username=username,
                                password=password)
        scp_client = scp.SCPClient(self.ssh_client.get_transport())
        scp_client.get(srcfile, destfile, recursive=True)
        scp_client.close()

    def _scp_put(self, hostname=None, username=None, password=None, srcfile=None, destfile=None):
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

