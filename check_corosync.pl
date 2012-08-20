#!/usr/bin/perl
# Simple corosync ring check, reports any errors

use warnings;
use strict;

my $sudo = "/usr/bin/sudo";
my $corosync_cfgtool = "/usr/sbin/corosync-cfgtool";

my $fh;
my $ringid;
my @status;
my $errors = 0;
my $exitval = 0;

open($fh, "$sudo $corosync_cfgtool -s |") or die "Unable to run sudo: $!\n";

foreach my $line (<$fh>) {
    chomp $line;
    if ($line =~ m/RING ID (\d+)/) {
        $ringid = $1;
    }
    if ($line =~ m/status\s+= (.*)/) {
        if ($1 =~ /active/) {
            push(@status, "Ring $ringid - OK");
        } else {
            push(@status, "Ring $ringid - FAULTY");
            $errors++;
        }
    }
}

if ($errors == scalar(@status)) {
    # no available communications methods
    print "CRIT: ";
    $exitval = 2;
} elsif ($errors) {
    print "WARN: ";
    $exitval = 1;
} else {
    print "OK: ";
    $exitval = 0;
}
print join(", ", @status) . "\n";

exit $exitval;
