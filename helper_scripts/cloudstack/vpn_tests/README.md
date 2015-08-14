Setup infra to test site-to-site VPN functionality
====

When you run ``./run_test.sh`` it will:

- Create two VPCs with one tier each
- Create a VPN gateway for each
- Creates a VPN Customer Gateway for each
- Create VPNs between them
- Spin a VM in each tier

This should bring up everything you need.

To see the status of the VPN, run ``ipsec auto --status``

The final lines should show you the connection is established.

What works and what not
----
By design, you need to test from the VMs in each tear to see if they can reach each other. Trying from one router to the other
routers tier does not work due to ``iptables`` rules.

``VM1 <--> router1 <--> ipsec tunnel <--> router2 <--> VM2``

``VM1`` and ``VM2`` sould be able to ping each other (and ssh if allowed) on their internal ip's without the need for port forwarding or such.
Using their consoles is usually the easiest way.

Known issues
----- 
Beware of CLOUDSTACK-8685: We need a default gateway before site-to-site VPN will actually work. It will connect, but not forward packets.
The reason for this, is due to the ``iptables`` setup. ``VM1`` has ``router1`` as gateway, but ``router1`` does not know the route to ``VM2`` so it
will give up. With a default gateway, the packets are about to be forwarded to the default gateway but when they reach ``eth1`` the public
nic, ``iptables`` kicks in, does some magic and forwards it through the ``ipsec`` tunnel. So, you need a default gw set to upstream.

Workaround for now is setting the route manually:
``route add default gw 1.2.3.4`` or ``# ip route add default via 1.2.3.4``

TODO
----
We should write this stuff in Marvin.
