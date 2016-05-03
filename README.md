HYPERION-LIRC
=============

Hyperion-lirc is a simple perl script that connects to lircd to listen for remote control presses.

It then calls hyperion to set the led colours and adjust the brightness.

I have included a sample lircd.conf which was recorded from an Aldi led pool light.

* lircd needs to be running with --listen

* you will need to modify the perl script
** $lirc_remote_name - The name of the remote control from lircd.conf
** $lirc_host - which host is lirc running ? (make sure it has --listen)

** $hyperion_host - Which host and port is hyperion running on?
** $hyperion_port 

