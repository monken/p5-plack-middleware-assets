use strict;
use warnings;
use Test::More 0.88;
use Plack::Builder;
use HTTP::Request::Common;
use Plack::Test;

our $time;
BEGIN {
    require Time::Local; # core
    $time = Time::Local::timegm(37, 50, 14, 29, 11-1, 2011);
    *CORE::GLOBAL::time = sub () { $time };
    require Plack::Middleware::Assets;
}

my $app = builder {
    enable "Assets", files => [<t/static/*.js>];
    enable "Assets",
        files  => [<t/static/*.css>],
        minify => 0;
    enable "Assets", files => [<t/static/*.js>], minify => 0, type => 'css';
    enable "Assets", files => [<t/static/*.css>], minify => 2, expires => 300;
    return sub {
        my $env = shift;
        [   200,
            [ 'Content-type', 'text/plain' ],
            [ map { $_ . $/ } @{ $env->{'psgix.assets'} } ]
        ];
        }
};

my $assets;
my $total = 4;

my %test = (
    client => sub {
        my $cb = shift;
        {
            my $res = $cb->( GET 'http://localhost/' );
            is( $res->code, 200 );
            $assets = [ split( $/, $res->content ) ];
            is( @$assets, $total );
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

        {
            my $res = $cb->( GET 'http://localhost' . $assets->[2] );
            is( $res->code,         200 );
            is( $res->content_type, 'text/css', 'type set explicitly' );
            is( $res->header('Expires'), 'Thu, 29 Dec 2011 14:50:37 GMT', 'default expiration');
            is( $res->content,  qq</* t/static/js1.js */
function() {
    foo
};
/* t/static/js2.js */
js2()>,
            );
        }

        {
            my $res = $cb->( GET 'http://localhost' . $assets->[3] );
            is( $res->code,         200 );
            is( $res->content_type, 'text/css' );
            is( $res->header('Expires'), 'Tue, 29 Nov 2011 14:55:37 GMT', 'expiration set low');
            is( $res->content, qq{css1
css2},
            'minify set explicitly');
        }

    },
    app => $app,
);

test_psgi %test;

done_testing;
