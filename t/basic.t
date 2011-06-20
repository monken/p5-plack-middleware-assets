use strict;
use warnings;
use Test::More 0.88;
use Plack::Builder;
use HTTP::Request::Common;
use Plack::Test;

my $app = builder {
    enable "Assets", files => [<t/static/*.js>];
    enable "Assets",
        files  => [<t/static/*.css>],
        minify => 0;
    return sub {
        my $env = shift;
        [   200,
            [ 'Content-type', 'text/plain' ],
            [ map { $_ . $/ } @{ $env->{'psgix.assets'} } ]
        ];
        }
};

my $assets;

my %test = (
    client => sub {
        my $cb = shift;
        {
            my $res = $cb->( GET 'http://localhost/' );
            is( $res->code, 200 );
            $assets = [ split( $/, $res->content ) ];
            is( @$assets, 2 );
        }

        {
            my $res = $cb->( GET 'http://localhost' . $assets->[0] );
            is( $res->code,         200 );
            is( $res->content_type, 'application/javascript' );
            is( $res->content,      'function(){foo};js2()' );
        }

        {
            my $res = $cb->( GET 'http://localhost' . $assets->[1] );
            is( $res->code,         200 );
            is( $res->content_type, 'text/css' );
            is( $res->content, qq{/* t/static/css1.css */
css1
/* t/static/css2.css */
css2}
            );
        }
    },
    app => $app,
);

test_psgi %test;

done_testing;
