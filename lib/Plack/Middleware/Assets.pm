package Plack::Middleware::Assets;

# ABSTRACT: Concatenate and minify JavaScript and CSS files
use strict;
use warnings;

use base 'Plack::Middleware';
use Plack::Util::Accessor qw( filename_comments filter content minify files key mtime type expires );

use Digest::MD5 qw(md5_hex);
use JavaScript::Minifier::XS ();
use CSS::Minifier::XS        ();
use HTTP::Date               ();

my %content_types = (
    css  => 'text/css',
    js   => 'application/javascript',
);

# these can be names or coderefs
my %minifiers = (
    css => 'CSS::Minifier::XS::minify',
    js  => 'JavaScript::Minifier::XS::minify',
);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->_build_content;
    return $self;
}

sub _build_content {
    my $self = shift;
    local $/;
    $self->filename_comments(1) unless defined $self->filename_comments;
    $self->content(
        join(
            "\n",
            map {
                open my $fh, '<', $_ or die "$_: $!";
                ($self->filename_comments ? "/* $_ */\n" : '') . <$fh>
                } @{ $self->files }
        )
    );
    $self->type( ( grep {/\.css$/} @{ $self->files } ) ? 'css' : 'js' )
        unless ( $self->type );

    $self->minify(
        # don't minify if we don't know how
        $minifiers{ $self->type } &&
            # by default don't minify in development
            ($ENV{PLACK_ENV} ? $ENV{PLACK_ENV} ne 'development' : 1)
    )
        unless ( defined $self->minify );

    if( my $filter = $self->filter ){
        local $_ = $self->content;
        $self->content( $filter->( $_ ) );
    }
    $self->content( $self->_minify ) if $self->minify;

    $self->key( md5_hex( $self->content ) );
    my @mtime = map { ( stat($_) )[9] } @{ $self->files };
    $self->mtime( ( reverse( sort(@mtime) ) )[0] );
}

sub _minify {
    my $self = shift;
    no strict 'refs';
    return $self->content unless
        my $method = $minifiers{ $self->minify } || $minifiers{ $self->type };
    return $method->( $self->content );
}

sub serve {
    my $self         = shift;
    my $type         = $self->type;
    my $content_type = $content_types{ $type } || $type;

    return [
        200,
        [
            'Content-Type'   => $content_type,
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

  # or customize your assets as desired:

  builder {
      # concatenate any arbitrary content type
      enable Assets =>
          files  => [<static/less/*.less>],
          type   => 'text/less',
          minify => 'css';

      # concatenate sass files and transform them into css
      enable Assets =>
          files  => [<static/sass/*.sass>],
          type   => 'text/css',
          filter => sub { Text::Sass->new->sass2css( shift ) },
          minify => 'css';

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

The concatenated and minified content is cached in memory.

=head1 DEVELOPMENT MODE

 $ plackup app.psgi
 
 $ starman -E development app.psgi

In development mode the minification is disabled and the
concatenated content is regenerated if there were any changes
to the files.

=head1 CONFIGURATIONS

=over 4

=item filename_comments

Boolean.  By default files are prepended with C</* filename */\n>
before being concatenated.

=item files

Files to concatenate.

=item filter

A coderef that can process/transform the content.

The current content will be passed in as C<$_[0]>
and also available via C<$_> for convenience.

This will be called before it is minified (if C<minify> is enabled).

=item minify

Value to indicate whether to minify or not. Defaults to C<1>.

Besides a boolean you can also set this to a string to use a predefined
minifier (which can be useful if you change the type):

=item type

Type of the asset.
Predefined types include C<css> and C<js>.
If set to an arbitrary type this will become the C<Content-Type>.

An attempt to guess the correct value is made from the file extensions
but this can be set explicitly if you are using non-standard file extensions.

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
