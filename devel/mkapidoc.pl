################################################################################
#
#  mkapidoc.pl -- generate apidoc.fnc from scanning the Perl source
#
# Should be called from the base directory for Devel::PPPort.
# If that happens to be in the /dist directory of a perl build structure, and
# you're doing the standard thing, no parameters are required.  Otherwise
# (again with the standard things, its single parameter is the base directory
# of the perl source tree to be used.
#
################################################################################
#
#  Version 3.x, Copyright (C) 2004-2013, Marcus Holland-Moritz.
#  Version 2.x, Copyright (C) 2001, Paul Marquess.
#  Version 1.x, Copyright (C) 1999, Kenneth Albanowski.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the same terms as Perl itself.
#
################################################################################

use warnings;
use strict;
use File::Find;

my $PERLROOT = $ARGV[0];
unless ($PERLROOT) {
    $PERLROOT = '../..';
    print STDERR "$0: perl directory root argument not specified. Assuming '$PERLROOT'\n";
}

die "'$PERLROOT' is invalid, or you haven't successfully run 'make' in it"
                                                unless -e "$PERLROOT/warnings.h";
    
my $config= "$PERLROOT/config_h.SH";
my %seen;

# Find the files in MANIFEST that are core, but not embed.fnc, nor .t's
my @files;
open(my $m, '<', "$PERLROOT/MANIFEST") || die "MANIFEST:$!";
while (<$m>) {                      # In embed.fnc,
    chomp;
    next if m! ^ embed \. fnc \t !x;
    next if m! ^ ( cpan | dist | t) / !x;
    next if m! [^\t]* \.t \t !x;
    s/\t.*//;
    push @files, "$PERLROOT/$_";
}
close $m;

# Examine the SEE ALSO section of perlapi which should contain links to all
# the pods with apidoc entries in them.  Add them to the MANIFEST list.
my $file;

sub callback {
    return unless $_ eq $file;
    return if $_ eq 'config.h';   # We don't examine this one
    return if $_ eq 'perlintern.pod';   # We don't examine this one
    return if $File::Find::dir =~ / \/ ( cpan | dist | t ) \b /x;
    push @files, $File::Find::name;
}

open my $a, '<', "$PERLROOT/pod/perlapi.pod"
        or die "Can't open perlapi.pod ($PERLROOT needs to have been built): $!";
while (<$a>) {
    next unless / ^ =head1\ SEE\ ALSO /x;
    while (<$a>) {
        # The lines look like:
        # F<config.h>, L<perlintern>, L<perlapio>, L<perlcall>, L<perlclib>,
        last if / ^ = /x;
        my @tags = split /, \s* | \s+ /x;  # Allow comma- or just space-separated
        foreach my $tag (@tags) {
            if ($tag =~ / ^ F< (.*) > $ /x) {
                $file = $1;
            }
            elsif ($tag =~ / ^ L< (.*) > $ /x) {
                $file = "$1.pod";
            }
            else {
                die "Unknown tag '$tag'";
            }

            find(\&callback, $PERLROOT);
        }
    }
}

# Look through all the files that potentially have apidoc entries
my @entries;
for (@files) {

    s/ \t .* //x;
    open my $f, '<', "$_" or die "Can't open $_: $!";

    my $line;
    while (defined ($line = <$f>)) {
        chomp $line;
        next unless $line =~ /^ =for \s+ apidoc \s+ 
                             (  [^|]* \|        # flags
                                [^|]* \|        # return type
                              ( [^|]* )         # name
                                (?: \| .* )?    # optional args
                             ) /x;
        my $meat = $1;
        my $name = $2;

        if (exists $seen{$name}) {
            if ($seen{$name} ne $meat) {
                print STDERR
                    "Contradictory prototypes for $name,\n$seen{$name}\n$meat\n";
            }
            next;
        }

        $meat =~ s/[ \t]+$//;
        $seen{$name} = $meat;

        # Many of the entries omit the "d" flag to indicate they are
        # documented, but we wouldn't have found this unless it was documented
        # in the source
        $meat =~ s/\|/d|/ unless $meat =~ /^[^|]*d/;

        push @entries, "$meat\n";
    }
}

# The entries in config_h.SH are also (documented) macros that are
# accessible to XS code, and ppport.h backports some of them.  We
# use only the unconditionally compiled parameterless ones (as
# that"s all that"s backported so far, and we don"t have to know
# the types of the parameters).
open(my $c, "<", $config) or die "$config: $!";
my $if_depth = 0;   # We don"t use the ones within #if statements
                    # The #ifndef that guards the whole file is not
                    # noticed by the code below
while (<$c>) {
    $if_depth ++ if / ^ \# [[:blank:]]* (ifdef | if\ defined ) /x;
    $if_depth -- if $if_depth > 0 && / ^ \# [[:blank:]]* endif /x;
    next unless $if_depth <= 0;

    # We are only interested in #defines with no parameters
    next unless /^ \# [[:blank:]]* define [[:blank:]]+
                        ( [A-Za-z][A-Za-z0-9]* )
                        [[:blank:]]
                /x;
    next if $seen{$1}; # Ignore duplicates
    push @entries, "Amnd||$1\n";
    $seen{$1}++;
}
close $c or die "Close failed: $!";

open my $out, ">", "parts/apidoc.fnc"
                        or die "Can't open 'parts/apidoc.fnc' for writing: $!";
require "./parts/inc/inctools";
print $out <<EOF;
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:
:  !!!! Do NOT edit this file directly! -- Edit devel/mkapidoc.sh instead. !!!!
:
:  This file was automatically generated from the API documentation scattered
:  all over the Perl source code. To learn more about how all this works,
:  please read the F<HACKERS> file that came with this distribution.
:
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:
: This file lists all API functions/macros that are documented in the Perl
: source code, but are not contained in F<embed.fnc>.
:
EOF
print $out sort sort_api_lines @entries;
close $out or die "Close failed: $!";
print "$outfile regenerated\n";
