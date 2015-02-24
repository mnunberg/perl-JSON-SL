#!/usr/bin/perl
use Test::More;
use JSON::SL;

eval {
    JSON::SL->new->feed(undef)
}; ok($@);
done_testing();
