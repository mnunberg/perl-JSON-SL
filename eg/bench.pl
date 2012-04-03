#!/usr/bin/perl
use strict;
use warnings;
use blib;
use JSON::SL;
use Data::Dumper::Concise;
use JSON::XS qw(decode_json);
use Time::HiRes qw(time);
use Getopt::Long;

GetOptions(
    'i|iterations=i' => \my $Iterations,
    'x|jsonxs' => \my $TestJsonxs,
    's|jsonsl' => \my $TestJsonsl,
    'j|jpr' => \my $TestJsonpointer,
    'c|chunked=i' => \my $TestChunks,
    'f|file=s'  => \my $TESTFILE,
    'r|recursion=i' => \my $RecursionLimit,
    'd|dump'    => \my $DumpTree,
    'h|help' => \my $PrintHelp
);

if ($PrintHelp) {
    print STDERR <<EOF;
$0 [options]
    -i --iterations=NUM Number of iterations
    -x --jsonxs             Benchmark JSON::XS
    -s --jsonsl             Benchmark JSON::SL
    -j --jpr                Test JSONPointer functionality
    -f --file=FILE          Run benchmarks on FILE
    -c --chunked=SIZE       Test incremental chunks of SIZE bytes
    -r --recursion=LEVEL    Set JSON::SL recursion limit
    -d --dump               Dump object tree on completion
EOF
    exit(1);
}

$Iterations ||= 20;

if ($ENV{PERL_JSONSL_DEFAULTS}) {
    $TestJsonsl = 1;
    $TestJsonxs = 1;
    $TestJsonpointer = 1;
    $TestChunks = 8192;
}

$TESTFILE ||= "share/auction";
$RecursionLimit ||= 256;

my $o = JSON::SL->new($RecursionLimit);
open my $fh, "<", $TESTFILE or die "$TESTFILE: $!";
my $txt = join("", <$fh>);
close($fh);

if ($TestJsonpointer) {
    $o->set_jsonpointer(["/alliance/auctions/^/auc"]);
    my $copy = substr($txt, 0, 246);
    my @all = $o->feed($copy);
    print $copy ."\n";
    print Dumper(\@all);
    print Dumper($o->root);
}
my ($begin,$duration);

if ($TestJsonxs) {
    $begin = time();
    foreach (0..$Iterations) {
        my $res = decode_json($txt);
    }
    $duration = time() - $begin;
    printf("$Iterations Iterations: JSON::XS %0.2f\n", $duration);
}

if ($TestJsonsl) {
    $begin = time();
    foreach (0..$Iterations) {
        my $res = JSON::SL::decode_json($txt);
    }
    my $duration = time() - $begin;
    printf("$Iterations Iterations: JSON::SL %0.2f\n", $duration);
}

my @Chunks;
if ($TestChunks) {
    my $copy = $txt;
    while ($copy) {
        my $len = length($copy);
        my $chunk = $TestChunks;
        $chunk = $len if $chunk > $len;
        my $frag = substr($copy, 0, $chunk);
        $copy = substr($copy, $chunk);
        push @Chunks, $frag;
    }
    
    printf("Testing chunked/incremental parsing with %d %dB chunks\n",
           scalar @Chunks, $TestChunks);
    if ($TestJsonxs) {
        $begin = time();
        my $xs = JSON::XS->new();
        for (0..$Iterations) {
            $xs->incr_reset();
            foreach my $chunk (@Chunks) {
                last if !$chunk;
                my @o = $xs->incr_parse($chunk);
            }
        }
        $duration = time() - $begin;
        printf("$Iterations iterations: JSON::XS %0.2f\n",
               $duration);
    }
    
    if ($TestJsonsl) {
        my $sl = JSON::SL->new($RecursionLimit);
        $begin = time();
        
        for (0..$Iterations) {
            $sl->reset();
            foreach my $chunk (@Chunks) {
                last if !$chunk;
                my @o = $sl->feed($chunk);
            }
        }
        $duration = time() - $begin;
        printf("$Iterations iterations: JSON::SL %0.2f\n",
               $duration);
    }
}