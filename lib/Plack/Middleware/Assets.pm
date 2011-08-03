package Plack::Middleware::Assets;

# ABSTRACT: Concatenate and minify JavaScript and CSS files
use strict;
use warnings;

use base 'Plack::Middleware';
__PACKAGE__->mk_accessors(qw(content minify files key mtime type expires));

use Digest::MD5 qw(md5_hex);
use JavaScript::Minifier::XS ();
use CSS::Minifier::XS        ();
use HTTP::Date               ();

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->_build_content;
    return $self;
}

sub _build_content {
    my $self = shift;
    local $/;
    $self->content(
        join(
            "\n",
            map {
                open my $fh, '<', $_ or die "$_: $!";
                "/* $_ */\n" . <$fh>
                } @{ $self->files }
        )
    );
    $self->type( ( grep {/\.css$/} @{ $self->files } ) ? 'css' : 'js' )
        unless ( $self->type );
    $self->minify(1) unless ( defined $self->minify );
    $self->content( $self->_minify ) if $self->minify;

    $self->key( md5_hex( $self->content ) );
    my @mtime = map { ( stat($_) )[9] } @{ $self->files };
    $self->mtime( ( reverse( sort(@mtime) ) )[0] );
}

sub _minify {
    my $self = shift;
    no strict 'refs';
    my $method
        = $self->type eq 'css'
        ? 'CSS::Minifier::XS::minify'
        : 'JavaScript::Minifier::XS::minify';
    return $method->( $self->content );
}

sub serve {
    my $self         = shift;
    my $content_type = return [
        200,
        [     'Content-Type' => $self->type eq 'css'
            ? 'text/css'
            : 'application/javascript',
            'Content-Length' => length( $self->content ),
            'Last-Modified'  => HTTP::Date::time2str( $self->mtime ),
            'Expires' =>
                HTTP::Date::time2str( time + ( $self->expires || 2592000 ) ),
        ],
        [ $self->content ]
    ];
}

sub call {
    my $self = shift;
    my $env  = shift;

    if ( $ENV{PLACK_ENV} && $ENV{PLACK_ENV} eq 'development' ) {
        my @mtime = map { ( stat($_) )[9] } @{ $self->files };
        $self->_build_content
            if ( $self->mtime < ( reverse( sort(@mtime) ) )[0] );
    }

    $env->{'psgix.assets'} ||= [];
    my $url = '/_asset/' . $self->key;
    push( @{ $env->{'psgix.assets'} }, $url );
    return $self->serve if $env->{PATH_INFO} eq $url;
    return $self->app->($env);
}

1;

__END__

=head1 SYNOPSIS

  # in app.psgi
  use Plack::Builder;

  builder {
      enable "Assets",
          files => [<static/js/*.js>];
      enable "Assets",
          files => [<static/css/*.css>],
          minify => 0;
      $app;
  };

  # $env->{'psgix.assets'}->[0] points at the first asset.

=head1 DESCRIPTION

Plack::Middleware::Assets concatenates JavaScript and CSS files
and minifies them. A C<md5> digest is generated and used as
unique url to the asset. The C<Last-Modified> header is set to
the C<mtime> of the most recently changed file. The C<Expires>
header is set to one month in advance. Set
L</expires> to change the time of expiry.

The concatented and minified content is cached in memory.

=head1 DEVELOPMENT MODE

 $ plackup app.psgi
 
 $ starman -E development app.psgi

In development mode the minification is disabled and the
concatenated content is regenerated if there were any changes
to the files.

=head1 CONFIGURATIONS

=over 4

=item files

Files to concatenate.

=item minify

Boolean to indicate whether to minify or not. Defaults to C<1>.

=item type

Type of the asset. Either C<css> or C<js>. This is derived automatically
from the file extensions but can be set explicitly if you are using
non-standard file extensions.

=item expires

Time in seconds from now (i.e. C<time>) until the resource expires.

=back

=head1 TODO

Allow to concatenate documents from URLs, such that you can have a
L<Plack::Middleware::File::Sass> that converts SASS files to CSS and
concatenate those with other CSS files. Also concatenate content from
CDNs that host common JavaScript libraries.

=head1 SEE ALSO

L<Catalyst::Plugin::Assets>

Inspired by L<Plack::Middleware::JSConcat>
