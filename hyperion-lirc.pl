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
		if ( &colour_name_to_rgb("$button") ) {
			&update_hyperion (&colour_name_to_rgb("$button"), $val);
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
		my ($s, $usec) = gettimeofday(); printf ("%1d\.%06d: ", $s%10, $usec);
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

sub colour_name_to_rgb() {

	%colour_list = (
	    'aliceblue'		,'[240, 248, 255]',
	    'antiquewhite'	,'[250, 235, 215]',
	    'aqua'		,'[ 0, 255, 255]',
	    'aquamarine'	,'[127, 255, 212]',
	    'azure'		,'[240, 255, 255]',
	    'beige'		,'[245, 245, 220]',
	    'bisque'		,'[255, 228, 196]',
	    'black'		,'[ 0, 0, 0]',
	    'blanchedalmond'	,'[255, 235, 205]',
	    'blue'		,'[ 0, 0, 255]',
	    'blueviolet'	,'[138, 43, 226]',
	    'brown'		,'[165, 42, 42]',
	    'burlywood'		,'[222, 184, 135]',
	    'cadetblue'		,'[ 95, 158, 160]',
	    'chartreuse'	,'[127, 255, 0]',
	    'chocolate'		,'[210, 105, 30]',
	    'coral'		,'[255, 127, 80]',
	    'cornflowerblue'	,'[100, 149, 237]',
	    'cornsilk'		,'[255, 248, 220]',
	    'crimson'		,'[220, 20, 60]',
	    'cyan'		,'[ 0, 255, 255]',
	    'darkblue'		,'[ 0, 0, 139]',
	    'darkcyan'		,'[ 0, 139, 139]',
	    'darkgoldenrod'	,'[184, 134, 11]',
	    'darkgray'		,'[169, 169, 169]',
	    'darkgreen'		,'[ 0, 100, 0]',
	    'darkgrey'		,'[169, 169, 169]',
	    'darkkhaki'		,'[189, 183, 107]',
	    'darkmagenta'	,'[139, 0, 139]',
	    'darkolivegreen'	,'[ 85, 107, 47]',
	    'darkorange'	,'[255, 140, 0]',
	    'darkorchid'	,'[153, 50, 204]',
	    'darkred'		,'[139, 0, 0]',
	    'darksalmon'	,'[233, 150, 122]',
	    'darkseagreen'	,'[143, 188, 143]',
	    'darkslateblue'	,'[ 72, 61, 139]',
	    'darkslategray'	,'[ 47, 79, 79]',
	    'darkslategrey'	,'[ 47, 79, 79]',
	    'darkturquoise'	,'[ 0, 206, 209]',
	    'darkviolet'	,'[148, 0, 211]',
	    'deeppink'		,'[255, 20, 147]',
	    'deepskyblue'	,'[ 0, 191, 255]',
	    'dimgray'		,'[105, 105, 105]',
	    'dimgrey'		,'[105, 105, 105]',
	    'dodgerblue'	,'[ 30, 144, 255]',
	    'firebrick'		,'[178, 34, 34]',
	    'floralwhite'	,'[255, 250, 240]',
	    'forestgreen'	,'[ 34, 139, 34]',
	    'fuchsia'	        ,'[255, 0, 255]', # "fuscia" is incorrect but common
	    'fuscia'	        ,'[255, 0, 255]', # mis-spelling...
	    'gainsboro'		,'[220, 220, 220]',
	    'ghostwhite'	,'[248, 248, 255]',
	    'gold'		,'[255, 215, 0]',
	    'goldenrod'		,'[218, 165, 32]',
	    'gray'		,'[128, 128, 128]',
	    'grey'		,'[128, 128, 128]',
	    'green'		,'[ 0, 128, 0]',
	    'greenyellow'	,'[173, 255, 47]',
	    'honeydew'		,'[240, 255, 240]',
	    'hotpink'		,'[255, 105, 180]',
	    'indianred'		,'[205, 92, 92]',
	    'indigo'		,'[ 75, 0, 130]',
	    'ivory'		,'[255, 255, 240]',
	    'khaki'		,'[240, 230, 140]',
	    'lavender'		,'[230, 230, 250]',
	    'lavenderblush'	,'[255, 240, 245]',
	    'lawngreen'		,'[124, 252, 0]',
	    'lemonchiffon'	,'[255, 250, 205]',
	    'lightblue'		,'[173, 216, 230]',
	    'lightcoral'	,'[240, 128, 128]',
	    'lightcyan'		,'[224, 255, 255]',
	    'lightgoldenrodyellow','[250, 250, 210]',
	    'lightgray'		,'[211, 211, 211]',
	    'lightgreen'	,'[144, 238, 144]',
	    'lightgrey'		,'[211, 211, 211]',
	    'lightpink'		,'[255, 182, 193]',
	    'lightsalmon'	,'[255, 160, 122]',
	    'lightseagreen'	,'[ 32, 178, 170]',
	    'lightskyblue'	,'[135, 206, 250]',
	    'lightslategray'	,'[119, 136, 153]',
	    'lightslategrey'	,'[119, 136, 153]',
	    'lightsteelblue'	,'[176, 196, 222]',
	    'lightyellow'	,'[255, 255, 224]',
	    'lime'		,'[ 0, 255, 0]',
	    'limegreen'		,'[ 50, 205, 50]',
	    'linen'		,'[250, 240, 230]',
	    'magenta'		,'[255, 0, 255]',
	    'maroon'		,'[128, 0, 0]',
	    'mediumaquamarine'	,'[102, 205, 170]',
	    'mediumblue'	,'[ 0, 0, 205]',
	    'mediumorchid'	,'[186, 85, 211]',
	    'mediumpurple'	,'[147, 112, 219]',
	    'mediumseagreen'	,'[ 60, 179, 113]',
	    'mediumslateblue'	,'[123, 104, 238]',
	    'mediumspringgreen'	,'[ 0, 250, 154]',
	    'mediumturquoise'	,'[ 72, 209, 204]',
	    'mediumvioletred'	,'[199, 21, 133]',
	    'midnightblue'	,'[ 25, 25, 112]',
	    'mintcream'		,'[245, 255, 250]',
	    'mistyrose'		,'[255, 228, 225]',
	    'moccasin'		,'[255, 228, 181]',
	    'navajowhite'	,'[255, 222, 173]',
	    'navy'		,'[ 0, 0, 128]',
	    'oldlace'		,'[253, 245, 230]',
	    'olive'		,'[128, 128, 0]',
	    'olivedrab'		,'[107, 142, 35]',
	    'orange'		,'[255, 165, 0]',
	    'orangered'		,'[255, 69, 0]',
	    'orchid'		,'[218, 112, 214]',
	    'palegoldenrod'	,'[238, 232, 170]',
	    'palegreen'		,'[152, 251, 152]',
	    'paleturquoise'	,'[175, 238, 238]',
	    'palevioletred'	,'[219, 112, 147]',
	    'papayawhip'	,'[255, 239, 213]',
	    'peachpuff'		,'[255, 218, 185]',
	    'peru'		,'[205, 133, 63]',
	    'pink'		,'[255, 192, 203]',
	    'plum'		,'[221, 160, 221]',
	    'powderblue'	,'[176, 224, 230]',
	    'purple'		,'[128, 0, 128]',
	    'red'		,'[255, 0, 0]',
	    'rosybrown'		,'[188, 143, 143]',
	    'royalblue'		,'[ 65, 105, 225]',
	    'saddlebrown'	,'[139, 69, 19]',
	    'salmon'		,'[250, 128, 114]',
	    'sandybrown'	,'[244, 164, 96]',
	    'seagreen'		,'[ 46, 139, 87]',
	    'seashell'		,'[255, 245, 238]',
	    'sienna'		,'[160, 82, 45]',
	    'silver'		,'[192, 192, 192]',
	    'skyblue'		,'[135, 206, 235]',
	    'slateblue'		,'[106, 90, 205]',
	    'slategray'		,'[112, 128, 144]',
	    'slategrey'		,'[112, 128, 144]',
	    'snow'		,'[255, 250, 250]',
	    'springgreen'	,'[ 0, 255, 127]',
	    'steelblue'		,'[ 70, 130, 180]',
	    'tan'		,'[210, 180, 140]',
	    'teal'		,'[ 0, 128, 128]',
	    'thistle'		,'[216, 191, 216]',
	    'tomato'		,'[255, 99, 71]',
	    'turquoise'		,'[ 64, 224, 208]',
	    'violet'		,'[238, 130, 238]',
	    'wheat'		,'[245, 222, 179]',
	    'white'		,'[255, 255, 255]',
	    'whitesmoke'	,'[245, 245, 245]',
	    'yellow'		,'[255, 255, 0]',
	    'yellowgreen'	,'[154, 205, 50]',
	);
	return ($colour_list{$_[0]});

};
