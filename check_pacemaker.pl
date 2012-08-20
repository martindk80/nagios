#!/usr/bin/perl
#
# check_pacemaker
# Originally based on: check_crm_v0_5
#		http://exchange.nagios.org/directory/Plugins/Clustering-and-High-2DAvailability/Check-CRM/details
#

use warnings;
use strict;
use Getopt::Long;

my $sudo    = '/usr/bin/sudo';
my $crm_mon = '/usr/sbin/crm_mon';

my $fh;

my $cluster_status;
my $output;
my $error_count = 0;
my @errors;
my $error_level = 'WARN';
my $error_exit = 1;

my %options;
GetOptions  (
    'h|help'    => \$options{'help'},
    'c|crit'    => \$options{'crit'},
    's|standby' => \$options{'standby'},
);

if ($options{'help'}) {
    print <<EOF;
-h,--help
    help
-c,--crit
    exit with CRITICAL status for any resource errors
-s,--standby
    exit with error status if any nodes in STANDBY status
EOF
    exit 0;
}

if ($options{'crit'}) {
    $error_level = 'CRIT';
    $error_exit = 2;
}

unless ( -e $crm_mon) {
    print "$crm_mon not found!";
    exit 3;
}


open( $fh, "$sudo $crm_mon -1 -r -f|" ) or die "Unable to run sudo: $!\n";

STATUS: foreach my $line (<$fh>) {
    chomp $line;

    # Check can connect and override exit status if failed
    if ( $line =~ m/Connection to cluster failed\:(.*)/i ) {
        $output = "CRIT: Unable to connect to cluster: $1";
        $error_exit = 2;
        $error_count++;
        last STATUS;
    }
    # Check for Quorum and override exit status if failed
    elsif ( $line =~ m/Current DC:/ ) {
        if ( $line =~ m/([\w.\-]+) - partition with quorum$/ ) {
            $output = "UP: $1 has quorum";
        }
        else {
            $output = "DOWN: No quorum!";
            $error_exit = 2;
            $error_count++;
        }
    }
    # Count offline nodes
    elsif ( $line =~ m/^offline:\s*\[\s*(\S.*?)\s*\]/i ) {
        my @offline = split( /\s+/, $1 );
        my $numoffline = scalar @offline;
        push @errors, "$numoffline Nodes Offline";
        $error_count += $numoffline;
    }
    # Check for standby nodes (suggested by Sönke Martens)
    elsif ( $line =~ m/^node\s+(\S.*):\s*standby/i ) {
        if ($options{'standby'}) {
            push @errors, "$1 in standby";
            $error_count++;
        } else {
            $output .= "$1 in standby";
        }
    }
    # Check Resources Stopped
    elsif ( $line =~ m/([\w:-]*)\s+\(\S+\)\:\s+Stopped/ or $line =~ m/\s*stopped\:\s*\[\s*([\w:-]*)\s*\]/i) {
        push @errors, "$1 stopped";
        $error_count++;
    }
    # Check Failed Actions
    elsif ( $line =~ m/^Failed actions\:/ ) {
        push @errors, "FAILED actions detected";
        $error_count++;
    }
    # Check for unmanaged failed
    elsif ( $line =~ m/\s*(\S+?)\s+ \(.*\)\:\s+\w+\s+\w+\s+\(unmanaged\)\s+FAILED/ ) {
        push @errors, "$1 unmanaged FAILED";
        $error_count++;
    }
    # Check for errors
    elsif ( $line =~ m/\s*(\S+?)\s+ \(.*\)\:\s+not installed/i ) {
        push @errors, "$1 not installed";
        $error_count++;
    }
    # Check for resource Fail count
    elsif ( $line =~ m/\s*(\S+?):.*fail-count=(\d+)/i ) {
        push @errors, "$1 fail-count $2";
        $error_count += $2;
    }
}

close($fh);

if ($error_count) { 
    print "$output, $error_count errors \(" . join(", ", @errors) . "\)\n";
    exit $error_exit;
} else {
    print "$output\n";
    exit 0;
}
