#!/usr/bin/perl
use strict;
use warnings;
use JSON::SL;
use utf8;
use Test::More;

my $sl = JSON::SL->new();

my $txt = <<'EOT';
{
"ערך":"כתבה"
}
EOT

my $res = $sl->feed($txt);

ok($res, "Have result");
ok(exists $res->{"ערך"}, "have utf8 key");
is($res->{"ערך"}, "כתבה", "have utf8 value");

done_testing();