CMDS = {
    'MTU': {
        'kvm': [
            'sudo /usr/sbin/ip link set dev {dev} mtu 1600',
            'sudo /usr/sbin/ip link set dev virbr0 mtu 1600',
            'sudo /usr/sbin/ip link set dev virbr0.50 mtu 1600'
        ],
        'xenserver': [
            'sudo /usr/sbin/ip link set dev {h} mtu 1500',
            'sudo /usr/sbin/ip link set dev virbr0 mtu 1500',
            'sudo /usr/sbin/ip link set dev virbr0.50 mtu 1500'
        ]
    },
    'generic': [
        'sudo /usr/sbin/ifup virbr0.50'
    ],
    'deploy': '/data/shared/deploy/kvm_local_deploy.py -m {marvin_config} --force {cloudstack_deploy_mode} 2>&1',
    'agent_install': {
        'precommands': [
            'systemctl daemon-reload',
            'systemctl stop cosmic-agent 2>&1 >/dev/null || true',
            'systemctl disable cosmic-agent 2>&1 >/dev/null || true',
            'rm -rf /opt/cosmic/',
            'rm -rf /etc/cosmic/',
            'rm -rf /var/log/cosmic/',
            'rm -f /usr/lib/systemd/system/cosmic-agent.service',
            'rm -f /usr/bin/cosmic-setup-agent',
            'rm -f /usr/bin/cosmic-ssh',
            'rm -rf /usr/lib64/python2.7/site-packages/cloudutils',
            'rm -f /usr/lib64/python2.7/site-packages/cloud_utils.py',
            'mkdir -p /opt/cosmic/agent/vms/',
            'mkdir -p /etc/cosmic/agent/'
        ],
        'scp': [
            ['cosmic-agent/target/cloud-agent-*.jar', '/opt/cosmic/agent/'],
            ['cosmic-agent/src/test/resources/application.yml', '/etc/cosmic/agent/'],
            ['cosmic-core/scripts/src/main/resources/scripts', '/opt/cosmic/agent/'],
            ['cosmic-core/systemvm/dist/systemvm.iso', '/opt/cosmic/agent/vms/'],
            ['cosmic-agent/bindir/cosmic-setup-agent.py', '/usr/bin/cosmic-setup-agent'],
            ['cosmic-agent/bindir/cosmic-ssh', '/usr/bin/'],
            ['cosmic-core/scripts/src/main/resources/python/lib/cloud_utils.py', '/usr/lib64/python2.7/site-packages/'],
            ['cosmic-core/scripts/src/main/resources/python/lib/cloudutils', '/usr/lib64/python2.7/site-packages/'],
            ['cosmic-agent/conf/cosmic-agent.service', '/usr/lib/systemd/system/']
        ],
        'postcommands': [
            'systemctl daemon-reload',
            'chmod -R 0755 /opt/cosmic/agent/scripts/',
            'chmod 0755 /usr/bin/cosmic-setup-agent',
            'chmod 0755 /usr/bin/cosmic-ssh'
        ]
    },
    'war_deploy': {
        'precommands': [
            'mkdir -p /etc/cosmic/management',
            'mkdir -p /var/log/cosmic/management',
            'chown -R tomcat /var/log/cosmic'
        ],
        'scp': [
            ['{setup_files}/client.xml', '/etc/tomcat/Catalina/localhost/'],
            ['{setup_files}/db.properties', '/etc/cosmic/management'],
            ['{setup_files}/kafka.producer.properties', '/etc/cosmic/management'],
            ['{setup_files}/context.xml', '/etc/tomcat'],
            ['{mariadbjar}', '/usr/share/java/tomcat/mariadb-java-client-latest.jar'],
            ['{war_file}', '~tomcat/webapps/client.war']
        ],
        'postcommands': [
            'systemctl restart tomcat'
        ]
    }
}