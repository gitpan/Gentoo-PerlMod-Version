use strict;
use warnings;

package Gentoo::PerlMod::Version;
BEGIN {
  $Gentoo::PerlMod::Version::VERSION = '0.001.000';
}

# ABSTRACT: Convert arbitrary Perl Modules' versions into normalised Gentoo versions.

use Sub::Exporter -setup => { exports => [qw( gentooize_version)] };
use Carp;
use List::MoreUtils qw( natatime );



sub gentooize_version {
  my ( $perlver, $config ) = @_;
  $config ||= {};
  $config->{lax} = 0 unless defined $config->{lax};

  if ( not _has_bad_bits($perlver) ) {
    return _lax_cleaning_0($perlver);
  }

  if ( $config->{lax} == 1 ) {
    return _lax_cleaning_1($perlver);
  }
  if ( $config->{lax} == 2 ) {
    return _lax_cleaning_2($perlver);
  }

  Carp::croak('Invalid version format (non-numeric data). ( set { lax => } for more permissive behaviour )');
}

###
#
# character to code translation
#
###

## no critic ( ProhibitMagicNumbers )
my $char_map = {
  ( map { $_ => $_ } 0 .. 9 ),    # 0..9
  ( map { chr( $_ + 65 ) => $_ + 10 } 0 .. 25 ),    # A-Z
  ( map { chr( $_ + 97 ) => $_ + 10 } 0 .. 25 )     # a-z
};

#
# _char_map() -> string of charmap dump
#
sub _char_map {
  require Data::Dumper;
  local $Data::Dumper::Sortkeys = 1;
  local $Data::Dumper::Terse    = 1;
  local $Data::Dumper::Indent   = 0;
  return Data::Dumper::Dumper($char_map);
}

#
# _code_for('z') -> $number
#

sub _code_for {
  my $char = shift;
  if ( !exists $char_map->{$char} ) {
    Carp::croak( 'Character ' . $char . q{ ( } . ord($char) . q{) is not in the ascii-to-int translation table} );
  }
  return $char_map->{$char};
}

###
#
# Pair to number transformation.
#
#   _enc_pair( 'x','y' ) ->  $number
#
##

sub _enc_pair {
  my (@tokens) = @_;
  if ( not @tokens ) {
    return q{};
  }
  if ( @tokens < 2 ) {
    return _code_for( shift @tokens );
  }
  return ( _code_for( $tokens[0] ) * 36 ) + ( _code_for( $tokens[1] ) );
}

###
#
#  String to dotted-decimal conversion
#
# $dotstring = _ascii_to_int("HELLOWORLD");
#
###
sub _ascii_to_int {
  my $string = shift;
  my @chars = split //, $string;
  my @output;

  my $iterator = natatime 2, @chars;
  while ( my @vals = $iterator->() ) {
    push @output, _enc_pair(@vals);
  }

  return join q{.}, @output;
}

# if( _has_bad_bits( $string )  ){
#   # do laxing?
# }

sub _has_bad_bits {
  return ( (shift) =~ /[^\d.]/ );
}

#
# Handler for gentooize_version( ... { lax => 0 } )
#
sub _lax_cleaning_0 {
  my $version = shift;
  return _expand_numeric($version);
}

#
# Handler for gentooize_version( ... { lax => 1 } )
#

sub _lax_cleaning_1 {
  my $version       = shift;
  my $isdev         = 0;
  my $prereleasever = undef;

  if ( $version =~ s/-TRIAL$// ) {
    $isdev = 1;
  }
  if ( $version =~ s/_(.*)$/$1/ ) {
    $prereleasever = "$1";
    $isdev         = 1;
    if ( $prereleasever =~ /_/ ) {
      Carp::croak(q{More than one _ in a version is not permitted});
    }
  }
  $version = _expand_numeric($version);
  if ($isdev) {
    $version .= '_rc';
  }
  return $version;
}

#
# Handler for gentooize_version( ... { lax => 2 } )
#

sub _lax_cleaning_2 {
  my $version = shift;
  my $istrial = 0;

  if ( $version =~ s/-TRIAL$// ) {
    $istrial = 1;
  }

  my @parts = split /([._])/, $version;
  my @out;
  for (@parts) {
    if ( $_ =~ /^[_.]$/ ) {
      push @out, $_;
      next;
    }
    if ( not _has_bad_bits($_) ) {
      push @out, $_;
      next;
    }
    push @out, _ascii_to_int($_);
  }

  my $version_out = join q{}, @out;
  if ($istrial) {
    $version_out .= '-TRIAL';
  }
  return _lax_cleaning_1($version_out);
}

#
# Expands dotted decimal to a float, and then chunks the float.
#

sub _expand_numeric {
  my $perlver = shift;

  my $numeric = version->parse($perlver)->numify;

  1 while $numeric =~ s/([.]\d\d\d)(\d+)$/$1.$2/;

  return $numeric;
}

1;

__END__
=pod

=head1 NAME

Gentoo::PerlMod::Version - Convert arbitrary Perl Modules' versions into normalised Gentoo versions.

=head1 VERSION

version 0.001.000

=head1 SYNOPSIS

    use Gentoo::PerlMod::Version qw( :all );

    # http://search.cpan.org/~gmpassos/XML-Smart-1.6.9/
    say gentooize_version( '1.6.9' )  # 1.006.009

    http://search.cpan.org/~pip/Math-BaseCnv-1.6.A6FGHKE/

    say gentooize('1.6.A6FGHKE')   #  <-- death, this is awful

    # -- Work-In-Progress Features --

    say gentooize('1.6.A6FGHKE',{ lax => 1}) # <-- still death

    say gentooize('1.6.A6FGHKE',{ lax => 2}) # 1.006.366.556.632.014  # <-- the best we can do.

    say gentooize('1.9902-TRIAL')   #  <-- death, this is awful

    say gentooize('1.9902-TRIAL', { lax => 1 })   #  1.990.200_rc # <-- -TRIAL gets nuked, 'rc' is added.

=head1 METHODS

=head2 gentooize_version

    my $normalized = gentooize_version( $weird_version )

gentooize_version tries hard to mangle a version that is part of a CPAN dist into a normalized form
for Gentoo, which can be used as the version number of the ebuild, while storing the original upstream version in the ebuild.

    CPAN: Foo-Bar-Baz 1.5
    print gentooize_version('1.5');  # -> 1.500
    -> dev-perl/Foo-Bar-Baz-1.500.ebuild
    cat dev-perl/Foo-Bar-Baz-1.500.ebuild
    # ...
    # MODULE_VERSION="1.5"
    # ...

Normal behaviour accepts only sane non-testing versions, and expands them to the form of \d(.\d\d\d)+ i.e.:

    0.1         -> 0.100
    0.001       -> 0.001
    1.1         -> 1.100
    1.123.13    -> 1.123.013

Etc.

This uses L<< C<version.pm>|version >> to read versions and to normalize them to floating-point form, and the floating point form
is sliced into arbitrary parts 3-digits long. i.e.:

    $x = version->parse( 0.01 )->numify;   # 0.010
    $x =~ s/(\.\d\d\d)(\d+)$/$1.$2/;       # 0.010
    $x = version->parse( 0.001 )->numify;  # 0.001
    $x =~ s/(\.\d\d\d)(\d+)$/$1.$2/;       # 0.001
    $x = version->parse( 0.0001 )->numify; # 0.000100
    $x =~ s/(\.\d\d\d)(\d+)$/$1.$2/;       # 0.000.100

So assuming Perl can handle your versions, they can be normalised.

=head3 lax level 1

    my $nomralized = gentooize_version( $werid_version, { lax => 1 } );

B<EXPERIMENTAL:> This feature is still in flux, and the emitted versions may change.

This adds one layer of laxativity, and permits parsing and processing of "Developer Release" builds.

    1.10-TRIAL  # 1.100_rc
    1.11-TRIAL  # 1.110_rc
    1.1_1       # 1.110_rc

=head3 lax level 2

    my $nomralized = gentooize_version( $werid_version, { lax => 2 } );

B<EXPERIMENTAL:> This feature is still in flux, and the emitted versions may change.

This adds another layer of laxativity, and permits parsing and processing of packages with versions not officially supported by Perl.

This means versions such as

    1.6.A       # 1.006.010
    1.6.AA      # 1.006.370
    1.6.AAA      # 1.006.370.010
    1.6.AAAA      # 1.006.370.370

    1.6.A6FGHKE # 1.006.366.556.632.014

This is performed by some really nasty tricks, and treats the ASCII portion like a set of pairs.

    1.6.A6.FG.HK.E

And each ascii pair is treated like a Base36 number.

    0 -> 0
    ....
    9 -> 9
    A -> 10
    ...
    Z -> 35

A6 is thus

    10 * 36 + 6 => 366

As you can see, its really nasty, and hopefully its not needed.

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Kent Fredric <kentnl@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

