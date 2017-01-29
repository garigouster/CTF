#!/usr/bin/env perl

# A tool to download writeups of RingZer0 Team
# By garigouster

use strict;
use warnings qw(all);

use DateTime::Format::Strptime;
use File::Basename;
use File::Spec::Functions;
use HTML::TreeBuilder::XPath;
use LWP::UserAgent;

my $cookie = $ARGV[0];
my @challenge = map {/^\d{1,3}$/ ? $_ ? int : () : /^ALL$/i ? 'ALL' : ()} @ARGV[1..$#ARGV];

die 'Usage: ',basename($0)," cookie ALL | challenge_number ...\n" if !defined $cookie || !@challenge || @challenge != @ARGV-1 || grep {/ALL/} @challenge && @ARGV != 2;

my $host = 'https://ringzer0team.com';
my $chUrl = $host . '/challenges';
my $wuUrl = $chUrl . '/wu';

my $rootDir = '.';

my $all = (grep {/ALL/} @challenge) ? 1 : 0;

my $ua = LWP::UserAgent->new(
    keep_alive => 1,
    default_headers => HTTP::Headers->new(Cookie => 'PHPSESSID='.$cookie),
);

sub GetChallenges() {
    print "Searching challenges...\n";

    my $req = $ua->get($chUrl);
    die 'HTTP error: ',$req->status_line if !$req->is_success;

    my @xpc = HTML::TreeBuilder::XPath->new_from_content($req->content)->findnodes('//table[@class="table table-striped table-bordered"]/tbody/tr/td/a[@href =~ /^\/challenges\//]');
    die 'Bad XPATH query' if !@xpc;

    my %challenge;

    for (@xpc) {
        my $name = $_->findvalue('.');
        my $number = $_->findvalue('./@href');

        ($number) = $number =~ /^\/challenges\/(\d{1,3})\s*$/;

        $challenge{$number} = $name;
    }

    %challenge;
}

sub GetWriteups($$) {
    my ($number,$name) = @_;

    $number = int $number;
    $name =~ s/[<>:"\/\\|?*]/./g;

    my $dir = catdir $rootDir,sprintf '/rzt-ch%03d - %s',$number,$name;

    printf "Challenge %03d: Searching writeups...\n",$number;

    my $req = $ua->get($wuUrl.'/'.$number);

    # No writeup or error on webpage?
    if (!$req->is_success && $req->code == 302) {
        printf "Challenge %03d: No writeup.\n",$number;
        return;
    }

    die 'HTTP error: ',$req->status_line if !$req->is_success;

    my $tree = HTML::TreeBuilder::XPath->new_from_content($req->content);

    my @xpe = $tree->findnodes('//div[@class = "alert alert-danger" and @role="alert"]');
    die 'Bad XPATH query' if @xpe > 1;

    if (@xpe) {
        printf "Challenge %03d: Not resolved.\n",$number;
        return;
    }

    if (!-e $dir) {
        print "Create directory: $dir\n";
        mkdir $dir or die "$dir: $!\n";
    }

    my @xpw = $tree->findnodes('//table[@class="table table-striped table-bordered"]/tbody/tr');

    if (!@xpw) {
        printf "Challenge %03d: No writeup.\n",$number;
        return
    }
    
    for (@xpw) {
        my @time = $_->findvalues('./td/span[@class = "points"]');
        die 'Bad XPATH query' if @time != 1;
        my $time = $time[0];

        my @profile = $_->findvalues('./td/a[@href =~ /^\/profile\//]');
        die 'Bad XPATH query' if @profile != 1;
        my $profile = $profile[0];

        my @doc = $_->findnodes('./td/a[@href =~ /\?doc=/]');
        die 'Bad XPATH query' if @doc != 1;
        my $doc = $doc[0];

        my $uri = $doc->findvalue('./@href');
        my $filename = $doc->findvalue('.');

        printf "Challenge %03d: Download writeup of: %s\n",$number,$profile;

        my $req = $ua->get($host.$uri);
        die 'HTTP error: ',$req->status_line if !$req->is_success;

        $profile =~ s/[<>:"\/\\|?*]/./g;

        my $file = catfile $dir,$profile.' # '.$filename;
        open my $fd,'>',$file or die "$file: $!\n";
        print $fd $req->content;
        close $fd or die "$file: $!\n";

        $time = DateTime::Format::Strptime->new(pattern => '%Y-%m-%d %T',time_zone => 'local')->parse_datetime($time)->epoch;
        if ($time) {
            utime $time,$time,$file or warn "utime: $!\n";
        } else {
            warn "Bad date file\n";
}   }   }

my %challenge = GetChallenges;

@challenge = sort {$a <=> $b} keys %challenge if $all;

print 'Challenges for writeups to download: ',join(' ',@challenge),"\n";

for (@challenge) {
    if (exists $challenge{$_}) {
        GetWriteups $_,$challenge{$_};
    } else {
        printf "Challenge %03d: Doesn't exist.\n",$_;
}   }

exit 0;
