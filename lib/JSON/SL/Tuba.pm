package JSON::SL::Tuba;
use strict;
use warnings;
use JSON::SL;
use Data::Dumper;
use Log::Fu;

sub start_JSON {
    log_info("");
}

sub end_JSON {
    log_info("");
}

sub start_OBJECT {
    log_info("");
}

sub end_OBJECT {
    log_info("");
}

sub start_HKEY {
    log_info("");
}

sub end_HKEY {
    log_info("");
}

sub start_STRING {
    log_info("");
}

sub end_STRING {
    log_info("");
}

sub start_LIST {
    log_info("");
}
sub end_LIST {
    log_info("");
}

sub start_NUMBER {
    log_info("");
}

sub end_NUMBER {
    log_info("");
}

sub start_DATA {
    my ($self,$data) = @_;
    log_infof("Got data: '%s'", $data);
}


##### Here be dragons, internal guts ######
my %ActionMap = (
    '+' => 'start',
    '-' => 'end'
);

my %TypeMap = (
    '{' => 'OBJECT',
    '[' => 'LIST',
    'c' => 'DATA',
    'D' => 'JSON',
    '#' => 'HKEY',
    '"' => 'STRING',
    '^' => 'SPECIAL',
);

sub new {
    my ($cls,%options) = @_;
    $cls->_initialize();
}



{
    no warnings 'once';
    *parse = *_parse;
}

sub _plhelper {
    my ($tuba,$action,$type,$data) = @_;
    my $action_prefix = $ActionMap{chr($action)};
    my $type_suffix = $TypeMap{chr($type)};
    if ($action_prefix && $type_suffix) {
        my $methname = sprintf("%s_%s", $action_prefix, $type_suffix);
        if (my $meth = $tuba->can($methname)) {
            $meth->($tuba, $data);
            return;
        } else {
            log_err("Couldn't locate method $methname");
        }
    } else {
        log_warnf("Got (unhandled) action=%s, type=%s", chr($action), chr($type));
    }
    if ($data) {
        log_infof("Data: %s", $data);
    }

    #my $methname = "$action_prefix\_$type_suffix";
    #warn "Will call '$methname'";
}

1;