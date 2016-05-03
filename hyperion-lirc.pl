#!/usr/bin/perl

use IO::Socket;
use IO::Handle ();
use IO::Select;
use Time::HiRes (gettimeofday);

$SIG{PIPE} = sub {
	print "got a sigpipe: $!\n";
	if ( (defined $lounge_socket) && ($lounge_socket->connected()) ) {
		print "lounge is connected\n";
	} else {
		print "lounge is not connected\n";
		$s->remove($lounge_socket);
	}
	$blah = $s->handles(); print "blah is $blah\n";
};

kill_previous();

$hostname = `hostname`;
chomp $hostname;

$lirc_remote_name = "aldi-pool-leds";

$loungehost = "loungepi.home";

$hyperion_host = "loungepi.home";
$hyperion_port = "19444";

$led_last_val=0.2;
$led_last_colour="[130,255,255]";
$led_brightness=4;	# 0..7

#$read_set = new IO::Select();
$s = IO::Select->new();

STDOUT->autoflush(1);

$pat_idx = 0;
@pat = ('/', '-', '\\', '|' );
sub print_next_pattern() {
	print $pat[$pat_idx++]."\b";
	$pat_idx %= 4;
}

sub check_sockets() {
&print_next_pattern;
# try to open sockets
	if (! ( (defined $lounge_socket) && ( print $lounge_socket "VERSION\n" ) )) {
		print "not defined or cant print to lounge_socket $! $@\n";
		$s->remove($lounge_socket);
		print "close lounge_socket\n";
		close ($lounge_socket);
		our $lounge_socket = new IO::Socket::INET (
			PeerAddr => $loungehost,
			PeerPort => '8765',
			Proto => 'tcp',
		);
		if ($lounge_socket) {
			print (STDERR "opened lounge_socket\n");
			$s->add($lounge_socket);
		} else {
			print (STDERR "cant open lounge_socket: $@\n");
			if ($@ =~ m/Bad hostname/) { print "Sleeping for 10\n"; sleep(10) }
		}
	}

}


while (1) {
	$this_time = time();
	if ($this_time - $last_time > 1) {
		$last_time = $this_time;
		&check_sockets;
	}

# get a set of readable handles (blocks until at least one handle is ready)

#	$blah = $s->handles(); print "watched handles: $blah\n";

	$timeout="";
	@read_ready = $s->can_read($timeout);

#	$blah = @read_ready; print "FDs ready for read: $blah\n";
	foreach $rh (@read_ready) {
		$text = <$rh>; {
#			if ($text) { print "RAW:".$rh->peerhost().":"."$text"; }

			if ($text =~ m/^([\da-f]+)\s(\d\d)\s(\S+)\s(\S+)$/) {
				($code, $repeat, $button, $control) = ($1,$2,$3,$4);
	#			print ("code $code control $control button $button repeat $repeat\n");
				&handle_press($rh, $code, $repeat, $button, $control);	
			}
		}
	}


}


sub open_sockets() {
	our $lounge_socket = new IO::Socket::INET (
		PeerAddr => $loungehost,
		PeerPort => '8765',
		Proto => 'tcp',
	);
	if ($lounge_socket) {
		print (STDERR "opened lounge_socket\n");
		$s->add($lounge_socket);
	} else {
		print "Could not create lounge_socket: $!\n";
	}


	our $hyp_socket = new IO::Socket::INET (
		PeerAddr => $hyperion_host,
		PeerPort => $hyperion_port,
		Proto => 'tcp',
	);
}

sub handle_press {
	my ($peer, $code, $repeat, $button, $control) = @_;
	my ($s, $usec) = gettimeofday(); printf ("%1d\.%06d: ", $s%10, $usec);
	print $peer->peerhost().":".$peer->peerport();
	print ("\tRECEIVE   \t$control $button $repeat\n");

	if ($control eq "$lirc_remote_name") {
		&handle_hyperion();
	}

}

sub close_sockets {
    print "close lounge_socket\n";
    close ($lounge_socket);
    printf ("sleeping ");
#    for ($i=0; $i<5; $i++) {
        sleep(1);
        print ".";
#    }
    printf (" restarting\n\n\n");
}


sub send_code {
	my ($control, $button, $repeat) = @_;
	my ($s, $usec) = gettimeofday(); printf ("%1d\.%06d: ", $s%10, $usec);
	$cmd = sprintf ("SEND_ONCE\t%s %s %s\n", $control, $button, $repeat);

	if (defined $lounge_socket) {
		print $lounge_socket->peerhost().":".$lounge_socket->peerport();
		print "\t$cmd";

		if ( print ($lounge_socket $cmd) ) {
		} else {
		    print "Error writing to socket: $!\n";
		    undef $lounge_socket;
		}
	} else {
		print "Error writing to socket.\n";
	}
}

sub send_codes {
    my $control = $_[0];
    foreach (split(/ /, $_[1])) {
        send_code ($control, $_, 0);
    }
}


sub kill_previous {
	$victim = "/usr/bin/perl /usr/local/bin/ir-repeater.pl";

	open(FILE, "ps -ef|");
	@psout = <FILE>;
	close FILE;
	foreach (@psout)
	{
		chomp;
		($uid,$pid,$ppid,$c, $stime, $tty, $time, $cmd) = split(/\s+/, $_,8);

		if ($cmd eq $victim) {
			if ($pid == $$) {
				print "ignoring me!\n";
			} else {
				print "killing pid=$pid $cmd \n";
				`kill $pid`;
			}
		}
	}
}

sub bright_to_val() {
	my $bright = $_[0];
	my $val;
	if ($bright == 0) {
		$val= 0;
		return 0;
	} else {
		$val= (2**$bright)/128;
		return  (2**$bright)/128;
	}
}

sub handle_hyperion {
#	$val = (2**$led_brightness)/128;
	$val = &bright_to_val($led_brightness);
	if ($repeat%2 == 0) {
		if ($button eq "bright_up") {
			$led_brightness+=1;
			if ($led_brightness>7) {$led_brightness = 7};
#			$val = (2**$led_brightness)/128;
			$val = &bright_to_val($led_brightness);

#			$val += 0.05;
#			if ($val>1) {$val = 1};
			&update_hyperion ( $val);
		}
		if ($button eq "bright_down") {
			$led_brightness-=1;
			if ($led_brightness<0) {$led_brightness = 0};
#			$val = (2**$led_brightness)/128;
			$val = &bright_to_val($led_brightness);

#			$val -= 0.05;
#			if ($val<0) {$val = 0};
			&update_hyperion ( $val);
		}
	}
	if ($repeat == 0) {
		if ($button eq "red") {
			&update_hyperion ("[255,0,0]", $val);
		}
		elsif ($button eq "green") {
			&update_hyperion ("[0,255,0]", $val);
		}
		elsif ($button eq "deepblue") {
			&update_hyperion ("[0,0,139]", $val);
		}
		elsif ($button eq "blue") {
			&update_hyperion ("[0,0,255]", $val);
		}
		elsif ($button eq "yellow") {
			&update_hyperion ("[255,255,0]", $val);
		}
		elsif ($button eq "orange") {
			&update_hyperion ("[255,165,0]", $val);
		}
		elsif ($button eq "lightgreen") {
			&update_hyperion ("[144,238,144]", $val);
		}
		elsif ($button eq "darkgreen") {
			&update_hyperion ("[0,100,0]", $val);
		}
		elsif ($button eq "skyblue") {
			&update_hyperion ("[135,206,235]", $val);
		}
		elsif ($button eq "lightblue") {
			&update_hyperion ("[0,255,255]", $val);
		}
		elsif ($button eq "purple") {
			&update_hyperion ("[128,0,128]", $val);
		}
		elsif ($button eq "pink") {
			&update_hyperion ("[255,192,203]", $val);
		}
		elsif ($button eq "magenta") {
			&update_hyperion ("[255,0,255]", $val);
		}
		elsif ($button eq "white") {
			&update_hyperion ("[255,255,255]", $val);
		}
	}
	if ($button eq "off") {
		&update_hyperion ("off");
	}
	if ($button eq "on") {
		&update_hyperion ($led_last_colour, $val);
	}
}


sub update_hyperion() {
# 1 argument - assumes HSV v change
	if (1==@_) {
		if ($_[0] eq "off") {
			change_colour("[0,0,0]",0);
		} else {
			my ($col, $val) = ($led_last_colour, $_[0]);
			change_v($val);
			$led_last_val = $val;
		}
	}
# 2 arguments, color and hsv V
	if (2==@_) {
		my ($col, $val) = ($_[0], $_[1]);
		change_colour($_[0],0);
		$led_last_colour = $col;
		change_v($val);
		$led_last_val = $val;
	}

}

sub change_colour {
        ($color_string, $priority) = @_;
        $request = '{"color":'.$color_string.',"command":"color","priority":'.$priority.'}'."\n";
        json_request($request);
}

sub change_v {
        ($HSV_val, $priority) = @_;
	$request = '{"command":"transform","transform":{"valueGain":'.$HSV_val.'}}'."\n";
        json_request($request);
}


sub json_request {
        $request = $_[0];

	if ( ($hyp_socket) && ($hyp_socket->connected)) {
#	       print "connected to the server\n";

	# data to send to a server
		my $size = $hyp_socket->send($request);
		chomp $request;
		print $hyp_socket->peerhost().":".$hyp_socket->peerport();
		print "\tHYPERION  \t$request";

	# receive a response of up to 1024 characters from server
		my $response = "";
		$hyp_socket->recv($response, 1024);
		chomp $response;
		if ($response ne '{"success":true}') {
			print "received response: $response\n";
		} else {
			print "\n";
		}

	} else {
		print "Connection to hyperion failed. Retrying...";
		if ($hyp_socket) {
			$hyp_socket->close();
		}
		our $hyp_socket = new IO::Socket::INET (
			PeerAddr => $hyperion_host,
			PeerPort => $hyperion_port,
			Proto => 'tcp',
		);
		if ($hyp_socket) {
			print " success!\n";
		} else {
			print " failed!\n";
		}
	}
}


