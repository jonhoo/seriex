#!/usr/bin/perl
use strict;
use warnings;
use File::Find;
use File::Copy;
use IMDB::Film;

die "Usage: $0 <folders>\n" if @ARGV == 0;

my $series;
do {
    print "Series: ";
    my $lookup = <STDIN>;
    chomp $lookup;

    $series = new IMDB::Film ( crit => $lookup );
    if ( !$series -> status ) {
        print "Found no matching series for query: " . $series -> error . "\n";
        next;
    }

    print "Found potential match for query:\n";
    print "Title:\t" . $series -> title() . "\n";
    print "Type:\t" . $series -> kind() . "\n";
    print "Year:\t" . $series -> year() . "\n";
    print "Plot:\t" . $series -> plot() . "\n";
    print "Is this correct? [Y/n] ";
} while ( <STDIN> =~ /^n/i );

my @episodes_raw = @{ $series -> episodes() };
my %seasons = ();
foreach my $episode ( @episodes_raw ) {
    $seasons { $episode -> { "season" } } = {} if not defined $seasons { $episode -> { "season" } };
    $seasons { $episode -> { "season" } } -> { $episode -> { "episode" } } = $episode -> { "title" };
}

my %renames = ();
find ( \&processFile, @ARGV ); 

print "Are you sure you want to rename all these files? [y/N] ";
die "Okay... I'll quit then...\n" if <STDIN> !~ /^y/i;

for my $dir (keys %renames) {
    chdir $dir;
    for my $f (keys %{ $renames { $dir } }) {
        my $newf = $renames { $dir } -> { $f };
        if ( -e $newf ) {
            print STDERR "Duplicate detected for rename '$f' --> '$newf'\n";
            next;
        }

        if ( !move ( $f, $newf ) ) {
            print STDERR "Failed to rename file '$f' to '$newf': $!\n";
            $newf =~ s/\s*\:\s*/ - /g;
            $newf =~ s/[^\&\,\'a-zA-Z0-9 \.\-]//g;
            print "Would you like to try '$newf' instead? [Y/n] ";
            if ( <STDIN> !~ /^n/i ) {
                move ( $f, $newf ) or print STDERR "Failed to rename file '$f' to '$newf' aswell: $!\n";
            }
        }
    }
}

sub processFile {
    return if -d $File::Find::name;
    $renames { $File::Find::dir } = {} if not defined $renames { $File::Find::dir };
    fixName($_, $renames { $File::Find::dir });
    setTitle($_, $renames { $File::Find::dir });
}

sub fixName {
    my $file = shift; 
    my $newnames = shift;
    my $newname = $file;
    
    return if $newname =~ /^S\d+E\d+/;

    $newname =~ s/_/ /g;
    $newname =~ s/^.*\[(\d+)\.(\d+)\]/S$1E$2 /g;
    while ( $newname =~ /\.(.*)\./ ) {
        $newname =~ s/\.(.*)\./ $1./g;
    }
    $newname =~ s/^.*\bS?(\d+)xE?(\d+)\b/S$1E$2 /g;
    $newname =~ s/^.*s(\d+)\s*e(\d+)\b/S$1E$2 /gi;
    $newname =~ s/^.*S(\d+)\s*Episode\s*(\d+)\b/S$1E$2 /gi;
    $newname =~ s/^.*Season\s*(\d+).*Episode\s*(\d+)\b/S$1E$2 /gi;

    $newname =~ s/\[[^\[]+\]//g;

    $newname =~ s/ - //g;
    $newname =~ s/^S(\d)E/S0$1E/g;
    $newname =~ s/^S(\d+)E(\d)\b/S$1E0$2/g;
    $newname =~ s/^(S\d+E\d+)/$1 - /g;
    $newname =~ s/ - \././g;
    $newname =~ s/\s{2,}/ /g;
    $newname =~ s/ - ]/ - /g;
    $newname =~ s/\s{2,}/ /g;
    $newname =~ s/\s+\././g;
    $newname =~ s/ -\././g;

    return if $newname !~ /^S\d+E\d+/;
    $newnames -> { $file } = $newname;
}

sub setTitle {
    my $file = shift; 
    my $newnames = shift;
    my $renamedTo = $file;
    $renamedTo = $newnames -> { $file } if defined $newnames -> { $file };

    return if $renamedTo !~ /^S(\d+)E(\d+).*\.(\w+)$/;
    if ( $file =~ /E\d+\-\d+/i || $file =~ /E\d{3,}/i ) {
        print STDERR "Careful! $file is a dual episode, and should be handled manually.\n";
        if ( $renamedTo ne $file ) {
            delete $newnames -> { $file };
        }
        return;
    }
    
    my $season = int $1;
    my $episode = int $2;
    my $ext = $3;
    return if not defined $seasons { $season } -> { $episode };
    
    my $newFileName = sprintf "S%02sE%02s - %s.%s", $season, $episode, $seasons { $season } -> { $episode }, $ext;
    print "$file --> $newFileName\n";
    $newnames -> { $file } = $newFileName;
}
