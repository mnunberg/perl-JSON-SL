package JSON::SL::EscapeTH;
use strict;
use warnings;

sub TIEHASH {
    my ($cls,$o) = @_;
    my $self = bless { pjsn => $o }, $cls;
    return $self;    
}

sub STORE {
    my $self = $_[0];
    $self->{pjsn}->_escape_table_chr(ord($_[1]), $_[2]);    
}

sub FETCH {
    my $self = $_[0];
    my $c = $_[1];
    # always unescape RFC 4627-mandated escaped characters
    $self->{pjsn}->_escape_table_chr(ord($_[1]));
}

sub EXISTS {
    goto &FETCH;
}

sub DELETE {
    $_[2] = 0;
    goto &STORE;
}

sub FIRSTKEY {
    my $self = $_[0];
    $self->{idx} = -1;
    $self->NEXTKEY;
}

sub NEXTKEY {
    my $self = $_[0];
    return if ++$self->{idx} > 0x7f;
    chr($self->{idx});
}

sub SCALAR {
    '127/127';
}

sub CLEAR {
    my $self = $_[0];
    $self->{pjsn}->_escape_table_chr($_, 0) foreach (0..0x7f);
}

1;