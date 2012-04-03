use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'JSON::SL',
    AUTHOR              => q{M. Nunberg <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/JSON/SL.pm',
    ABSTRACT_FROM       => 'lib/JSON/SL.pm',
    META_MERGE          => {
        resources => {
            repository => 'https://github.com/mnunberg/perl-JSON-SL/'
        }
    },

    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    OPTIMIZE            => '-Wall -ggdb3 -O3',
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'JSON-SL-*' },
);
