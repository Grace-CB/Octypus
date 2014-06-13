#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

# add my ~/lib directory
use lib '/home/grace/lib/';

use UUID::Tiny ':std';
use YAML::Any qw( Dump LoadFile ); #load up whatever YAML we're generally using
use Data::Dumper;

my $debug = 0;                                                          # Print debug messages.


# GENERAL CONFIGURATION

open(my $cfh, '< ', "../config/config.yaml") or die "Can't load config options.\n\n";

my $cfg = LoadFile($cfh); # Load the configuration options into memory.

if ($debug) { print Dumper $cfg; }

my ($test, $server, $iteration) = ($$cfg{'test'}, $$cfg{'server'}, $$cfg{'iterate'});
my ($s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst);
( $s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst ) = localtime(time);
my $stale = 1;                                                          # Don't generate fresh raw stuff, just grab the raw file in $stale_octypus.

my $stale_octypus = 'Raw_Octypus: Thursday_June-12-2014_at_17:34:29_ID_df5b38c8-39af-3dfe-91b0-edae44e998e8.txt';

if ($s < 10) { $s = ("0" . $s) };
if ($mi < 10) { $mi = "0" . $mi };

my @days = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday");
my @months = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December");

my $date = $days[$wd] . "_" . $months[$mo] . "-" . ($d) . "-" . ($y+1900);
my $time = $h . ":" . $mi . ":" . $s;

my $run_uuid = create_uuid_as_string(UUID_MD5, "$test$server$time$date");

my $current_raw_file = 'Raw_Octypus: ' . $date . "_at_" . $time . "_ID_" . $run_uuid . ".txt";
my $current_report_file = 'Cooked_Octypus: ' . $date . "_at_" . $time . "_ID_" . $run_uuid . ".txt";


# CONFIGURATION OF PLATFORMS TO TEST ON

open(my $pfh, '<', '../config/platforms.yaml') or die "Can't load platform list.\n\n";

my $platforms = LoadFile($pfh); # Load the platforms file into memory.

if ($debug) { print Dumper $platforms; }


if ( $stale ) {                                 # If we're working with stale Octypus, then we ignore 'new' file info and just fetch a specific raw file.

        $current_raw_file = $stale_octypus;

}

if ( $stale ) { goto STALE; }  			# NOT THE DREADED GOTO STATEMENT okay yes I used a goto statement in Perl

# OPEN UP THE RAW FILEHANDLE

open(my $rfh, '>', ('../output/raw/' . $current_raw_file)) or die "Can't open raw file $current_raw_file for storing results.";

my $test_and_platform;

foreach (@{$platforms}) {

        $test_and_platform = "$test using $$_[0] v. $$_[2] on $$_[1]";                  # Stash this to standardize and save typing complex refs

        if ($debug) { print "Just got into the platforms loop."; }

        ($s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst) = localtime(time);
        my $when = "$mo-$d-" . ($y + 1900) . " at $h:";
        if ($s < 10) { $when = $when . "$s"; } else { $when = $when . "0" . $s; }

        my $i = 0;

        while ($i < $iteration) {

                $i++;
                print "\n\n", qq(  >>> BEGIN RESULT $i FOR $test_and_platform on $when <<< ), "\n\n";           # Show in output.
                print $rfh "\n\n", qq(  >>> BEGIN RESULT $i FOR $test_and_platform on $when <<< ), "\n\n";      # Add to the raw result file.
                my $output = `/usr/local/bin/gless $test $server GE_BROWSER='$$_[0]' GE_PLATFORM='$$_[1]' GE_BROWSER_VERSION='$$_[2]'`;
                print $output;
                print $rfh $output;
                print "\n\n", qq(  >>> END RESULTS FOR $test_and_platform started on $when <<< ), "\n\n";       # Show in output.
                print $rfh "\n\n", qq(  >>> END RESULTS FOR $test_and_platform started on $when <<< ), "\n\n";  # Add to the raw result file.

        }


}


close($rfh);


# PROCESS RAW DATA INTO REPORT DATA

STALE: open($rfh, '<', ('../output/raw/' . $current_raw_file)) || die "Can't read raw file $current_raw_file for processing.";

my @reportlines;                                        # This is where the report lines will end up.
my @raw = <$rfh>;                                       # Stash the lines.
my $count = scalar(@raw);                               # Count the lines.
my $block = 0;                                          # Until we hear otherwise, do not assume we're in a test block.
my $catch = 0;
my $footer = 0;
my @states;

close( $rfh );

for ( my $current = 0; $current < $count; $current++) {

        $catch = 0;

        my $line = $raw[$current];
        my $prevline;
        my $nextline;
        if ($current > 0) { $prevline = $raw[$current - 1]; }
        $nextline = $raw[$current + 1];
        chomp($line);


        if ($line =~ /^  >>> END/) {

                $footer = 0;                                                    # End the footer if it's going.
                $catch = 1;                                                     # Capture the line.
                $block = 0;                                                     # Turn off this test block.

        }

        if ($line =~ /^  >>> BEGIN/) {

                $catch = 1;                                                     # Capture the line.
                $block = 1;                                                     # Turn on a new test block.

        }



        if ($block) {                                                           # These are things we only look for in the block.

                if ($footer) { $catch = 1; }


                if (($line =~ /^( ){6}[A-Za-z]+?/) && ($prevline =~ /^( ){4}/)) {

                        $catch = 1;                                             # Capture the first indented line for errors.

                }


                if (($line =~ /^( ){4}[A-Za-z]+?/) && ($nextline =~ /^( ){6}/)) {

                        $catch = 1;                                             # Capture the line just before indents for errors.

                }


                if (($line =~ /^Failing/) || ($line =~ /^[0-9]{1,4}/)) {

			$catch = 1;
                        $footer = 1;
                        if ($line =~ /^Failing/) { push @states, "FAILED"; }
			print Dumper @states;

                }

        }


        if ($debug) { print "On iteration $current, just before the catch check: catch = $catch, block = $block, footer = $footer\n"; }
        if ($debug) { print "Line: $line\n\n"; }

        if ($catch) { push @reportlines, $line . "\n"; }

}


print "Report finished. Saving.\n\n";


# print Dumper @reportlines;

open(my $repfh, '>', ('../output/reports/' . $current_report_file)) || die "Couldn't open $current_report_file to save sanitized results. \n";

foreach (@reportlines) {

        print $repfh $_;

}

print $repfh "\n";
print $repfh "  ************************************************************************************************************************ \n";
print $repfh "  >>";
if ($stale) { print $repfh "STALE RUN"; }
print $repfh "REPORT SUMMARY FOR $run_uuid on $date at $time << \n";
print $repfh "  ************************************************************************************************************************ \n";


my $number_of_results = scalar(@states);
if ($debug) { print ' *** DUMPER RESULTS FOR @final_analysis *** ', "\n"; print Dumper @states; }
if ($debug) { print Dumper $number_of_results; }

print "Okay, number of results = $number_of_results, and iteration count = $iteration.";

my $difference = $iteration - $number_of_results;

if ($debug) { print Dumper $difference; }

my $comparison;

if ($debug) { print Dumper $comparison; }

if ($difference > 0) { $comparison = "fewer"; }
if ($difference < 0) { $comparison = "more"; }

if ($comparison) {
	print "$iteration tests scheduled but $difference $comparison tests done. \n\n";
        print $repfh "  We were supposed to do $iteration but did $difference $comparison tests than indicated.\n";
        print $repfh "  >>There may be a problem with the underlying Ruby executions.<<\n\n";
}

if ($difference == 0) {

	print "  We did exactly the number of indicated tests: $number_of_results \n\n";
	print $repfh "  We did exactly the number of indicated tests: $number_of_results \n\n";

}


print "Generating final summary.\n";
print $repfh " ** FINAL SUMMARY ** \n";

my $i = 0;

foreach (@states) {

	$i++;
        print $repfh "Iteration $i $_ \n";

}

close($repfh);

if ($stale) { print " ** STALE RUN ** \n"; }

print "Octypus Report saved as $current_report_file. Thank you for using Octypus.\n\n";
