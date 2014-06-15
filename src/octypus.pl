#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

# add my ~/lib directory
use lib '/home/grace/lib/';

use UUID::Tiny ':std';
use Term::Spinner::Lite;
use YAML::Any qw( Dump LoadFile ); #load up whatever YAML we're generally using
use Data::Dumper;

my $gless_spinner = Term::Spinner::Lite->new(
	delay => '100000',
	spin_chars => [ qw(\/), qw(|), qw(\\), qw(-) ],
);

my $report_spinner = Term::Spinner::Lite->new(
	delay => '100000',
	spin_chars => [ qw(.), qw(o), qw(O), qw(o) ],
);

my $debug = '0';								# Make this command line settable.


# GENERAL CONFIGURATION

open(my $cfh, '< ', "../config/config.yaml") || notify("Can't load config options.") && expire();

my $cfg = LoadFile($cfh); # Load the configuration options into memory.
										# Make this command line settable.

debug ( ( Dumper $cfg ) );

my ($test, $iteration) = ($$cfg{'test'}, $$cfg{'iterate'});
my ($s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst);
( $s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst ) = localtime(time);


my $stale = '1';                                                        # Don't generate fresh raw stuff, just grab the raw file in $stale_octypus.
									# This option is for testing formatting and parsing in Octypus.
									# Make this command line settable.

my $stale_octypus = 'Raw_Octypus: Friday_Jun-13-114_at_0:43:24_ID_bde4af76-6f5e-3bbd-adb7-b53f17b002df.txt'; # Eventually replace with storing last raw fname

sub zerofy;								# I forward-declared these subs. They're actually defined near the end.
sub dayfy;								# They're only for prettifying date/time/etc. stuff, and making certain
sub monthfy;								# things (like notifying the user about stuff) easier to read.
sub yearfy;
sub notify;
sub expire;

$s = zerofy($s);
$mi = zerofy($mi);
$wd = dayfy($wd);
$d = zerofy($d);
$mo = monthfy($mo);

my $date = $wd . "_" . $mo . "-" . $d . "-" . $y;
my $time = $h . ":" . $mi . ":" . $s;

my $run_uuid = create_uuid_as_string(UUID_MD5, "$test $time $date");

my $current_raw_file = 'Raw_Octypus: ' . $date . "_at_" . $time . "_ID_" . $run_uuid . ".txt";
my $current_report_file = 'Cooked_Octypus: ' . $date . "_at_" . $time . "_ID_" . $run_uuid . ".txt";


# CONFIGURATION OF PLATFORMS TO TEST ON

open(my $pfh, '<', '../config/platforms.yaml') || notify ( "Can't load platform list." ) && expire();

my $platforms = LoadFile($pfh); # Load the platforms file into memory.

debug( (Dumper $platforms) );


if ( $stale ) {                                 # If we're working with stale Octypus, then we ignore 'new' file info and just fetch a specific raw file.

        $current_raw_file = $stale_octypus;
	goto STALE; 	 			# NOT THE DREADED GOTO STATEMENT okay yes I used a goto statement in Perl

}


# OPEN UP THE RAW FILEHANDLE

open(my $rfh, '>', ('../output/raw/' . $current_raw_file))
	|| notify ( "Can't open raw file $current_raw_file." )
	&& expire();

my $test_and_platform;

my $server;

foreach (@{$platforms}) {

        $test_and_platform = "$test using $$_[0] v. $$_[2] on $$_[1]";                  # Stash this to standardize and save typing complex refs
	$server = $$_[3];

        debug( "Just got into the platforms loop." );

        ($s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst) = localtime(time);

	$s = zerofy($s);
	$mi = zerofy($mi);
	$mo = monthfy($mo);
	$h = zerofy($h);
	$d = zerofy($d);
	$wd = dayfy($wd);
	$y = yearfy($y);

        my $when = "$mo-$d-$y at $h:$mi:$s";

        my $i = 0;

	my $test_desc = "$test_and_platform on $server at $when";

        while ($i < $iteration) {

                $i++;
                # print "\n\n", qq(  >>> BEGIN RESULT $i FOR $test_desc <<< ), "\n\n";  	        # Show in output.
                print $rfh "\n\n", qq(  >>> BEGIN RESULT $i FOR $test_desc <<< ), "\n\n";     		# Add to the raw result file.
                my $output = `/usr/local/bin/gless $test $server GE_BROWSER='$$_[0]' GE_PLATFORM='$$_[1]' GE_BROWSER_VERSION='$$_[2]'`;
                # print $output;
                print $rfh $output;
                # print "\n\n", qq(  >>> END RESULTS FOR $test_desc <<< ), "\n\n";       		# Show in output.
                print $rfh "\n\n", qq(  >>> END RESULTS FOR $test_desc <<< ), "\n\n";  			# Add to the raw result file.
		unless ($debug) { $gless_spinner->next(); }

        }

	$gless_spinner->done();

}


close($rfh);

# PROCESS RAW DATA INTO REPORT DATA

STALE: open($rfh, '<', ('../output/raw/' . $current_raw_file)) 
	|| notify ( "Can't read raw file $current_raw_file for processing." )
	&& expire();

$iteration = $iteration * scalar(@{$platforms});

my @reportlines;                                        # This is where the report lines will end up.
my @raw = <$rfh>;                                       # Stash the lines.
my $count = scalar(@raw);                               # Count the lines.
my $block = 0;                                          # Until we hear otherwise, do not assume we're in a test block.
my $catch = 0;
my $footer = 0;
my @states;
my $state = '';
my $flag = '0';

close( $rfh );

for ( my $current = 0; $current < $count; $current++ ) {

        $catch = 0;

        my $line = $raw[$current];
        my $prevline;
        my $nextline;
        if ($current > 0) { $prevline = $raw[$current - 1]; }
        $nextline = $raw[$current + 1];
        chomp($line);

        if ($line =~ /^  >>> BEGIN/) {
                $catch = '1';                                                   # debug ( "Catch this line." );
                $block = '1';                                                   # debug ( "Turn on the test block checks." );
                $flag = '0';                                                    debug ( "Clear the test flag." );
                $state = '';                                                    debug ( "Null the state, because we just started a test." );
        }


        if ($line =~ /^  >>> END/) {
                $footer = '0';                                                  debug ( "Turned off footer." );
                $catch = '1';                                                   # debug ( "Catch this line." );
                $block = '0';                                                   # debug ( "Turn off test block checks." );
		if ($flag eq '0') {
			$state = 'PASSED';					debug ( "Set the test passed." );
			$flag = '1';						debug ( "The test was flagged for a pass/fail state." );
		}
        }


        if ($block) {                                                           # These are things we only look for in the block.

                if ($footer) {
			$catch = '1';						# debug ( "Catch this line." );
		}

                if (($line =~ /^( ){6}[A-Za-z]+?/) && ($prevline =~ /^( ){4}/)) {
                        $catch = '1';                                           # debug ( "Catch this line." );
                }

                if (($line =~ /^( ){4}[A-Za-z]+?/) && ($nextline =~ /^( ){6}/)) {
                        $catch = '1';                                           # debug ( "Catch this line." );
                }

                if (($line =~ /^Failing/) || ($line =~ /^[0-9]{1,4}/)) {

			$catch = '1';						# debug ( "Catch this line." );
                        $footer = '1';						debug ( "Turned on footer." );
                        if ($line =~ /^Failing/) {
				$state = "FAILED";				debug ( "Set the test failed." );
				$flag = '1';					debug ( "The test was flagged for a pass/fail state." );
			}

                }

		# if ($state && $flag) { push @states, $state; $flag = '0'; }

        }

        debug ( "On iteration $current, just before the catch check: catch = $catch, block = $block, footer = $footer, flag = $flag" );
        # debug ( "Line is >> $line <<" );

        if ($state && $flag) { push @states, $state; debug ( "Pushed $state onto the array." ); $state = ''; }
        if ($catch) { push @reportlines, $line . "\n"; }
	unless ($debug) { $report_spinner->next(); }

}

$report_spinner->done();

notify ( "Report finished. Saving." );

if ($stale) { $current_report_file = "Stale_" . $current_report_file; }				# Tag the report file as a stale.

open(my $repfh, '>', ('../output/reports/' . $current_report_file))
	|| notify("Couldn't open $current_report_file.")
	&& expire();

foreach (@reportlines) { print $repfh $_; }

print $repfh "\n";
print $repfh "  ************************************************************************************************************************ \n";
print $repfh "  >>";
if ($stale) { print $repfh "STALE RUN"; }
print $repfh "REPORT SUMMARY FOR $run_uuid on $date at $time << \n";
print $repfh "  ************************************************************************************************************************ \n";


my $number_of_results = scalar(@states);			debug ( "Okay, number of results = $number_of_results, and iteration count = $iteration." );

my $difference = $iteration - $number_of_results;		debug ( "Difference: " . ( Dumper $difference ) );

debug ( "From iteration (" . $iteration . ") - results (" . $number_of_results . ")." );

if ($difference != '0') {

	my $message;

	if ($difference < 0) { $message = "$iteration tests scheduled but $difference more tests done."; }
	if ($difference > 0) { $message = ( "$iteration tests scheduled but " . abs($difference) . " fewer tests done." ); }

	notify ( " >> $message << " );
	notify ( " >> This might indicate a problem with the underlying Ruby executions. Check the raw file. << " );
	print $repfh "  >> $message << \n";
        print $repfh "  >> This might indicate a problem with the underlying Ruby executions. Check the raw file. <<\n\n";
}

if ($difference == '0') {

	print "  We did exactly the number of indicated tests: $number_of_results \n\n";
	print $repfh "  We did exactly the number of indicated tests: $number_of_results \n\n";

}


notify("Generating final summary.");

print $repfh " ** FINAL SUMMARY ** \n";

my $i = 0;

foreach (@states) {

	$i++;
        print $repfh "Iteration $i $_ \n";

}

close($repfh);

if ($stale) { print " ** STALE RUN ** \n"; }

notify("Octypus Report saved as $current_report_file. Thank you for using Octypus.");


sub zerofy { my $n = shift; if ($n < 10) { return "0$n"; } else { return $n; } }
sub dayfy { my $d = shift; my @days = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"); return $days[$d]; }
sub monthfy { my $m = shift; my @months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"); return $months[$m]; }
sub yearfy { my $y = shift;  return $y + 1900; }
sub notify { my $message = shift; print "$message\n"; }
sub expire { die "The octypus has passed on: $!\n"; }
sub debug { my $message = shift; if ($debug) { notify ( "  DEBUG>> $message" ); } }

