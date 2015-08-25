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
None.

TODO
----
We should write this stuff in Marvin.
