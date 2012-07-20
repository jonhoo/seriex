#!/usr/bin/perl
use strict;
use warnings;
use File::Find;
use File::Copy;
use IMDB::Film;
use Cwd;

die "Usage: $0 <folders>\n" if @ARGV == 0;

my $series;
do {
    print "Series: ";
    my $lookup = <STDIN>;
    chomp $lookup;

    $series = new IMDB::Film ( crit => $lookup );
    if ( !$series -> status ) {
        print "Found no matching series for query: " . $series -> error . "\n";
        exit 0;
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
    my $olddir = getcwd;
    chdir $dir;
    for my $f (keys %{ $renames { $dir } }) {
        my $newf = $renames { $dir } -> { $f };
        if ( -e $newf ) {
            print STDERR "Duplicate detected for rename '$f' --> '$newf'\n";
            next;
        }

        if ( !move ( $f, $newf ) ) {
            print STDERR "Failed to rename file '$f' to '$newf': $!\n";
            $newf =~ s/\s*[\:\/\\]\s*/ - /g;
            $newf =~ s/[^\&\,\'a-zA-Z0-9 \.\-]//g;
            print "Would you like to try '$newf' instead? [Y/n] ";
            if ( <STDIN> !~ /^n/i ) {
                move ( $f, $newf ) or print STDERR "Failed to rename file '$f' to '$newf' as well: $!\n";
            }
        }
    }
    chdir $olddir;
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
    
    #return if $newname =~ /^S\d+E\d+/;

    # These numbers may confuse, so we take them out
    $newname =~ s/480p//gi;
    $newname =~ s/720p//gi;
    $newname =~ s/1080p//gi;
    $newname =~ s/1080i//gi;
    $newname =~ s/x264//gi;
    $newname =~ s/h264//gi;
    $newname =~ s/\d+[MG]B//gi;

    $newname =~ s/_/ /g;
    $newname =~ s/^.*\[(\d+)\.(\d+)\]/S$1E$2 /g;
    while ( $newname =~ /\.(.*)\./ ) {
        $newname =~ s/\.(.*)\./ $1./g;
    }
    $newname =~ s/^.*\bS?(\d+)xE?(\d+)\b/S$1E$2 /g;
    $newname =~ s/^.*s(\d+)\s*e(\d+)\b/S$1E$2 /gi;
    $newname =~ s/^.*S(\d+)\s*Episode\s*(\d+)\b/S$1E$2 /gi;
    $newname =~ s/^.*Season\s*(\d+).*Episode\s*(\d+)\b/S$1E$2 /gi;
    $newname =~ s/^.*?(\d+)(\d{2})/S$1E$2 /g if $newname !~ /S\d+E\d+/;

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
    return if $newname eq $file;
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
    return if $file eq $newFileName;
    print "$file --> $newFileName\n";
    $newnames -> { $file } = $newFileName;
}
