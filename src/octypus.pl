#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

# add my ~/lib directory
use lib '/home/grace/lib/';

use UUID::Tiny ':std';
use YAML::Any qw( Dump LoadFile ); #load up whatever YAML we're generally using
use Data::Dumper;


# GENERAL CONFIGURATION

open(my $cfh, '< ', "../config/config.yaml") or die "Can't load config options.\n\n";

my $cfg = LoadFile($cfh); # Load the configuration options into memory.

print Dumper $cfg;

my $test = $$cfg{'test'};
my $server = $$cfg{'server'};
my $iteration = $$cfg{'iterate'};
my ($s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst);
( $s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst ) = localtime(time);
my $debug = 1;

my @final_analysis;

if ($s < 10) { $s = "0" . $s };
if ($mi < 10) { $mi = "0" . $mi };

my @days = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday");
my @months = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December");

my $date = $days[$wd] . "_" . $months[$mo] . "-" . ($d+1) . "-" . ($y+1900);
my $time = $h . ":" . $mi . ":" . $s;

my $run_uuid = create_uuid_as_string(UUID_MD5, "$test$server$time$date");

my $current_raw_file = 'Raw_Octypus: ' . $date . "_at_" . $time . "_ID_" . $run_uuid . ".txt";
my $current_report_file = 'Cooked_Octypus: ' . $date . "_at_" . $time . "_ID_" . $run_uuid . ".txt";


# CONFIGURATION OF PLATFORMS TO TEST ON

open(my $pfh, '<', '../config/platforms.yaml') or die "Can't load platform list.\n\n";

my $platforms = LoadFile($pfh); # Load the platforms file into memory.

print Dumper $platforms;


# OPEN UP THE RAW FILEHANDLE

open(my $rfh, '>', ('../output/raw/' . $current_raw_file)) or die "Can't open raw file $current_raw_file for storing results.";

my $test_and_platform;

foreach (@{$platforms}) {

	$test_and_platform = "$test using $$_[0] v. $$_[2] on $$_[1]";			# Stash this to standardize and save typing complex refs.

	if ($debug) { print "Just got into the platforms loop."; }

	($s, $mi, $h, $d, $mo, $y, $wd, $yd, $dst) = localtime(time);
	my $when = "$mo-$d-" . ($y + 1900) . " at $h:";
	if ($s < 10) { $when = $when . "$s"; } else { $when = $when . "0" . $s; }

	print "\n\n", qq(  >>> BEGIN RESULTS FOR $test_and_platform on $when <<< ), "\n\n";	# Show in output.
	print $rfh "\n\n", qq(  >>> BEGIN RESULTS FOR $test_and_platform on $when <<< ), "\n\n";	# Add to the raw result file.

	my $i = 0;

	while ($i < $iteration) {

		my $output = `/usr/local/bin/gless $test $server GE_BROWSER='$$_[0]' GE_PLATFORM='$$_[1]' GE_BROWSER_VERSION='$$_[2]'`;
		$i++;
		print $output;
		print $rfh $output;

	}

	# print $output; # change this to dump to a textfile after stripping out warnings, for ease of reading afterwards

        print "\n\n", qq(  >>> END RESULTS FOR $test_and_platform started on $when <<< ), "\n\n";	# Show in output.
	print $rfh "\n\n", qq(  >>> END RESULTS FOR $test_and_platform started on $when <<< ), "\n\n";	# Add to the raw result file. Refactor these?

}


close($rfh);


# PROCESS RAW DATA INTO REPORT DATA

open($rfh, '<', ('../output/raw/' . $current_raw_file)) || die "Can't read raw file $current_raw_file for processing.";

my @reportlines;			# The array for the lines we need for the report.
my @rawlines = <$rfh>;			# The array with all the raw lines from the output.
my $numlines = scalar(@rawlines);	# Get the number of lines so we can iterate but still pick lines.
my $footer = 0;				# The flag for whether we're in the footer.

# print "We're cooking with gas now.\n\n";

# print Dumper @rawlines;

my $state = "PASSED";			# Until we hear otherwise, assume the tests pass.

for ( my $linenum = 0; $linenum < $numlines; $linenum++) {

#	print "We began an iteration on line number $linenum of $current_raw_file.\n";
	my $line = $rawlines[$linenum];							# The line we're on.
	my $prevline; if ($linenum > 0) { $prevline = $rawlines[$linenum - 1]; }	# The line before this one, if there is one.
	my $caught = 0;									# Whether we've caught this line once. (We won't need 'em twice.)
	chomp ($line);
	if ($linenum > 0) { chomp ($prevline); }
	
	if ($line =~ /^  >>> BEGIN/ && !$caught) {
		push @reportlines, "$line\n\n";
		$caught = 1;
		if ($debug) { print "Beginning the report.\n"; }			# Add the results header line
	}

	if ($line =~ /^( ){6}/ && !$caught) {						# If a Ruby fail output block has started...
		if ($debug) { print "Detected an error indentation.\n"; }
		unless ($prevline =~ /^( ){6}/) {					# ...and the line before it isn't part of the output block...
			if ($debug) { print "Detected error line just previous.\n"; }
			push @reportlines, "$prevline \n\n";				# ...add it to the report so we know what failed.
			$caught = 1;
			if ($debug) { print "Caught an error line.\n"; }
		}
	}

	if ($line =~ /^Failing/ && !$caught) {
		push @reportlines, "$line\n";
		$footer = 1;
		$caught = 1;
		$state = "FAILED";
		if ($debug) { print "Caught the start of the footer.\n"; } 		# Add the 'Failing' line and signal the start of the footer
	}

	if ($line =~ /^[0-9]* scenario/ && !$caught) {
		push @reportlines, "$line\n";
		$caught = 1;
		$footer = 1;
		if ($debug) { print "Caught a scenario count line.\n"; }		# Mark footer started if the scenario line shows up.
	}

	if ($footer && !$caught) {
		push @reportlines, "$line \n";
		$caught = 1;
		if ($debug) { print "Caught a footer line.\n"; }			# Add any line we see while we're in the footer.
	}

	if ($line =~ /^  >>> END/ && !$caught) { 
		push @reportlines, "$line\n"; 						# Add the last line.
		push @reportlines, "           >>>>> $test_and_platform: $state <<<<<\n";
		push @final_analysis, "           >>>>> $test_and_platform: $state <<<<<\n";
		$caught = 1;
		$footer = 0;								# The footer's all finished now.
		if ($debug) { print "Caught the end of the footer.\n"; }
	}

}


print "Report finished. Saving.\n\n";


# print Dumper @reportlines;

open(my $repfh, '>', ('../output/reports/' . $current_report_file)) || die "Couldn't open $current_report_file to save sanitized results. \n";

foreach (@reportlines) { 

	print $repfh $_;

}

print $repfh "\n";
print $repfh "  ************************************************************************************************************************ \n";
print $repfh "  >> REPORT SUMMARY FOR $run_uuid on $date at $time << \n";
print $repfh "  ************************************************************************************************************************ \n";

my $number_of_results = scalar(@final_analysis);
my $difference = $iteration - $number_of_results;
my $comparison;

if ($difference > 0) { $comparison = "fewer"; }
if ($difference < 0) { $comparison = "more"; }

if ($comparison) {
	print $repfh "  We were supposed to do $iteration but did $difference $comparison tests than indicated.\n";
	print $repfh "  >>There may be a problem with the underlying Ruby executions.<<\n\n";
}

if ($difference == 0) { print $repfh "  We did exactly the number of indicated tests: $number_of_results \n\n"; }


foreach (@final_analysis) {

	print $repfh $_;

}

close($repfh);

print "Octypus Report saved as $current_report_file. Thank you for using Octypus.\n\n";

__END__
