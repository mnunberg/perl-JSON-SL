# JSON-SL. the JSON streaming library

`JSON::SL` is a Fast, Streaming, and Searchable JSON decoder, written
in Perl and C. It was designed from the ground up to be easily accessible and
searchable for partially received streamining content.

It uses an embedded C library `jsonsl` to do the streaming and most
of the dirty work.

JSON::SL allows you to use the
[JSONPointer](http://tools.ietf.org/html/draft-pbryan-zyp-json-pointer-02)
URI/path syntax to tell it about certain objects and elements which are of
interest to you. JSON::SL will then incrementally parse the input stream,
returning those selected objects to you as soon as they arrive.

In addition, the objects are returned with extra context information, which is
itself another JSONPointer path specifying the path from the root of the JSON
stream until the current object.

Since I hate SAX's callback interface, and since almost all the boilerplate
for a SAX interface needs to be done for just about every usage case, I have
decided to move over the core work of state stacking and such to the C library
itself. This means minimal boilerplate and ultra fast performance on your part.

## INSTALLATION

To install this module, run the following commands:

	perl Makefile.PL
	make
	make test
	make install
	
## Usage

> Taken from `perldoc JSON::SL`

An exampel of how to use it. 

	use JSON::SL;
    use Data::Dumper;
    
    my $txt = <<'EOT';
    {
        "some" : {
            "partial" : 42.42
        },
        "other" : {
            "partial" : "a string"
        },
        "complex" : {
            "partial": {
                "a key" : "a value"
            }
        },
        "more" : {
            "more" : "stuff"
    EOT
    
    my $json = JSON::SL->new();
    my $jpath = "/^/partial";
    $json->set_jsonpointer( [$jpath] );
    my @results = $json->feed($txt);
    
    foreach my $result (@results) {
        printf("== Got result (path %s) ==\n", $result->{Path});
        printf("Query was %s\n", $result->{JSONPointer});
        my $value = $result->{Value};
        if (!ref $value) {
            printf("Got scalar value %s\n", $value);
        } else {
            printf("Got reference:\n");
            print Dumper($value);
        }
        print "\n";
    }
    
Produces:

    == Got result (path /some/partial) ==
    Query was /^/partial
    Got scalar value 42.42
    
    == Got result (path /other/partial) ==
    Query was /^/partial
    Got scalar value a string
    
    == Got result (path /complex/partial) ==
    Query was /^/partial
    Got reference:
    $VAR1 = {
              'a key' => 'a value'
            };


# SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module with the
perldoc command.

    perldoc JSON::SL

You can also look for information at:

    RT, CPAN's request tracker
        http://rt.cpan.org/NoAuth/Bugs.html?Dist=JSON-SL

    AnnoCPAN, Annotated CPAN documentation
        http://annocpan.org/dist/JSON-SL

    CPAN Ratings
        http://cpanratings.perl.org/d/JSON-SL

    Search CPAN
        http://search.cpan.org/dist/JSON-SL/


# LICENSE AND COPYRIGHT

Copyright (C) 2012 M. Nunberg

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

