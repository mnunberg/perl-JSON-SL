#!/usr/bin/perl
package My::Giant::Tuba;
use strict;
use warnings;
use blib;
use JSON::SL::Tuba;
use Log::Fu;
use Getopt::Long;
use Data::Dumper::Concise;
use utf8;

GetOptions('f|file=s' => \my $InputFile,
           'c|chunk=i' => \my $ChunkSize,
           'i|iterations=i' => \my $Iterations,
           'a|accumulate' => \my $AccumAll,
           'q|quiet' => \$Log::Fu::SHUSH);

our @ISA = qw(JSON::SL::Tuba);
my $JSON;

$Iterations ||= 1;

if ($InputFile) {
    open my $fh, "<", $InputFile or die "$InputFile: $!";
    $JSON = join("", <$fh>);
    close($fh);
}
$JSON ||= <<'EOJ';
{
    "a" : "b",
    "c" : { "d" : "e" },
    "f" : [ "g", "h", "i", "j" ],
    "a number" : 0.4444444444,
    "a (false) boolean": false,
    "another (true) boolean" : true,
    "a null value" : null,
    "exponential" : 1.3413400E4,
    "an\tescaped key" : "a u-\u0065\u0073caped value",
    "שלום":"להראות"
    
}
EOJ

sub on_any {
    my ($tuba,$info,$data) = @_;
    
    #use constant comparisons
    if ($info->{Type} == TUBA_TYPE_JSON) {
        printf STDERR ("JSON DOCUMENT: %c\n\n", $info->{Mode});
        return;
    }
    
    # or use the mnemonic ones
    if ($info->{Key} && $info->{Mode} =~ m,[>\+],) {
        printf ('"%s" : ', $info->{Key});
    }
    
    if ($info->{Type} == TUBA_TYPE_STRING) {
        printf('"%s",' . "\n", $data || "<NO DATA>");
        
    } elsif ($info->{Type} =~ m,[\[\{],) {
        if ($info->{Mode} eq '+') {
            print $info->{Type} . "\n";
        } else {
            
            print $JSON::SL::Tuba::CloseTokens{$info->{Type}} . ",\n";
        }
    } else {
        if (defined $data) {
            print $data . ",\n"
        } else {
            die ("hrrm.. what have we here?")
                unless $info->{Type} == TUBA_TYPE_NULL;
            print "null\n";
        }
    }
}

sub new {
    my ($cls,%options) = @_;
    my $o = $cls->SUPER::new(%options);
    #the object itself is a hashref. Only a single key
    #is used by tuba, the very prominent '_TUBA' key. Don't delete it.
    $o->{my_private_data} = "hey there";
    
    #if you want to re-bless or do something funny, do it BEFORE
    #parse() is called..
    $o;
}

my @Chunks;
if ($ChunkSize) {
    @Chunks = unpack("(a$ChunkSize)*", $JSON);
} else {
    @Chunks = $JSON;
}

open my $devnull, ">", "/dev/null";
if ($Log::Fu::SHUSH) {
    select $devnull;
}



foreach (1..$Iterations) {
    my $o = My::Giant::Tuba->new();
    #we want complete strings/numbers/booleans
    $o->accum_all(1);
    
    #we will be using a single callback for everything. Don't bother looking up
    #individual callbacks
    $o->cb_unified(1);
    
    #don't deliver the key as a separate event.
    $o->accum_kv(1);
    
    $o->parse($_) for @Chunks;
}