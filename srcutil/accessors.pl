#!/usr/bin/perl
use strict;
use warnings;

# both these structures have typemaps and a common 'options' field:

my @options = (
    ["PLTUBA", "JSON::SL::Tuba", [qw(utf8 no_cache_mro cb_unified allow_unhandled)]],
    ["PLJSONSL", "JSON::SL", [qw(utf8 nopath noqstr max_size object_drip)]]
);

print <<"EOC";
# This file generated by '$0' and is meant to generate easy boolean
# getters and setters
EOC

foreach (@options) {
    my ($ctype,$pkgname,$opts) = @$_;
    print <<"EOC";

MODULE = JSON::SL PACKAGE = $pkgname PREFIX = $ctype\_

PROTOTYPES: DISABLED

EOC

    my $ix_counter = 1;
    my @defines;

    foreach my $optname (@$opts) {
        push @defines, ["$ctype\_OPTION_IX_$optname", $ix_counter, $optname];
        $ix_counter++;
    }

    foreach (@defines) {
        my ($macro,$val) = @$_;
        print "#define $macro $val\n";
    }

    print <<"EOC";

int
$ctype\__options($ctype* obj, ...)
    ALIAS:
EOC
    foreach (@defines) {
        my $macro = $_->[0];
        my $optname = $_->[2];
        printf(<<"EOC", $optname, $macro);
    %-15s = %s
EOC
    }

    print <<"EOC";
    CODE:
    RETVAL = 0;
    if (ix == 0) {
        die("Do not call this function (_options) directly");
    }
    if (items > 2) {
        die("Usage: %s(o, ... boolean)", GvNAME(GvCV(cv)));
    }

    switch(ix) {
EOC

    foreach (@defines) {
        my ($macro,$optname) = @{$_}[0,2];
        print <<"EOC";
    case $macro:
        RETVAL = obj->options.$optname;
        if (items == 2) {
            obj->options.$optname = SvIV(ST(1));
        }
        break;
EOC
    }

    print <<"EOC";
    default:
        die("Unrecognized IX!?");
        break;
    }
    OUTPUT: RETVAL

EOC

}