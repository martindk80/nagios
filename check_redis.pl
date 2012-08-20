#!/usr/bin/perl
#
# simple redis check
#       Connects via netcat
#       Checks last background save and replication

use warnings;
use strict;
use Getopt::Long;
use POSIX;

# defaults
my %options = (
    help          => 0,
    server        => 'localhost',
    port          => 6379,
    db            => 0,
    save_warn     => 180,
    save_crit     => 300,
    last_save_changes  => 10,
    no_save       => 0,
    no_slave_save => 0,
    rep_warn      => 180,
    rep_crit      => 300,
    timeout       => 10,
);


my $fh;
my %info;
my @crit_err;
my @warn_err;
my $exit_value = 0;

GetOptions  (
    'h|help'         => \$options{help},
    's|server=s'     => \$options{server},
    'p|port=i'       => \$options{port},
    'w|savewarn=i'   => \$options{save_warn},
    'c|savecrit=i'   => \$options{save_crit},
    'x|savechanges'  => \$options{last_save_changes},
    'd|nosave'       => \$options{no_save},
    'z|noslavesave'  => \$options{no_slave_save},
    'repwarn=i'      => \$options{rep_warn},
    'repcrit=i'      => \$options{rep_crit},
    't|timeout=i'    => \$options{timeout},
);

if ($options{'help'}) {
    print <<EOF;
-h,--help
    Help
-s,--server
    Server to query.
-p,--port
    Server port to query.
-d,--nosave
    Disable ALL last save alerting.
-z,--noslavesave
    Disable last save alerting for slaves.
-w,--savewarn
    WARN: Number of seconds since last background save.
-c,--savecrit
    CRIT: Number of seconds since last background save.
-x,--savechanges
    Number of changes since last save to trigger last background save check.
--repwarn
    WARN: Number of seconds to warn since last replication (Slave)
--repcrit
    CRIT: Number of seconds to warn since last replication (Slave)
EOF
    exit 0;
}


#my $check_command => "/usr/bin/timeout $options{timeout} $options{redis_cli} -h $options{server} -p $options{port} info 2>&1 |";
my $check_command = "(/bin/echo -en 'info\r\n'; sleep 0.1) | /usr/bin/nc -w $options{timeout} $options{server} $options{port} 2>&1|";
open($fh, $check_command) or die "Cannot connect to redis instance: $!";

foreach my $line (<$fh>) {
    # clean up non printable characters
    $line =~ /^(#|\W)/ and next;
    $line =~ s/\W$//g;

    my ($key, $value) = split(/:/, $line);
    $info{$key} = $value;
}
close($fh);

# check that we were returned valid data
unless ($info{redis_version}) {
    print "Error occurred connecting to redis instance: $options{server}:$options{port}\n";
    exit 2;
}

# check last save (seconds)
unless ($options{no_save} or ($info{role} eq 'slave' and $options{no_slave_save})) {
    $info{save_age} = time - $info{last_save_time};
    if ($info{changes_since_last_save} > $options{last_save_changes}) {
        if ($info{save_age} >= $options{save_crit}) {
            push(@crit_err,"Last bg save $info{save_age}s ago ($info{changes_since_last_save} changes since)");
        } elsif ($info{save_age} < $options{save_crit} and $info{save_age} >= $options{save_warn}) {
            push(@warn_err,"Last bg save $info{save_age}s ago ($info{changes_since_last_save} changes since)");
        } elsif ($info{last_bgsave_status} ne 'ok') {
            push(@crit_err,"Last background save FAILED ($info{changes_since_last_save} changes since)");
        }
    }
}

# check replication (seconds)
if ($info{role} eq 'slave') {
    if ($info{master_link_status} eq 'down') {
        push(@crit_err,"Master $info{master_host} DOWN");
    } elsif ($info{master_last_io_seconds_ago} == -1) {
        push(@crit_err,"No rep with master $info{master_host}");
    } elsif ($info{master_last_io_seconds_ago} >= $options{rep_crit}) {
        push(@crit_err,"Last rep with $info{master_host} $info{master_last_io_seconds_ago}s ago");
    } elsif ($info{master_last_io_seconds_ago} < $options{rep_crit} and $info{master_last_io_seconds_ago} >= $options{rep_warn}) {
        push(@warn_err,"Last rep with $info{master_host} $info{master_last_io_seconds_ago}s ago");
    }
}

# exit
if (@crit_err) {
    $exit_value = 2;
    print "$info{role} CRIT - " . join(', ',@crit_err) . "\n";
} elsif (@warn_err) {
    $exit_value = 1;
    print "$info{role} WARN - " . join(', ',@warn_err) . "\n";
} else {
    $exit_value = 0;
    printf "%s OK - Peak memory: %s, clients: %s", $info{role}, $info{'used_memory_peak_human'}, $info{connected_clients};
    if ($info{role} eq 'master') {
        printf ", slaves: %s", $info{connected_slaves};
        unless ($options{no_save}) { printf ", last save: %ss ago", $info{save_age}; };
    } else {
        printf ", last rep: %ss", $info{master_last_io_seconds_ago};
        unless ($options{no_save} or $options{no_slave_save}) { printf ", last save: %ss ago", $info{save_age}; };
    }
    print "\n";
}

exit $exit_value;
