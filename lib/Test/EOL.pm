package Test::EOL;

use strict;
use warnings;

use Test::Builder;
use File::Spec;
use FindBin qw($Bin);
use File::Find;

use vars qw( $VERSION $PERL $UNTAINT_PATTERN $PERL_PATTERN);

$VERSION = '0.6';

$PERL    = $^X || 'perl';
$UNTAINT_PATTERN  = qr|^([-+@\w./:\\]+)$|;
$PERL_PATTERN     = qr/^#!.*perl/;

my %file_find_arg = ($] <= 5.006) ? () : (
    untaint => 1,
    untaint_pattern => $UNTAINT_PATTERN,
    untaint_skip => 1,
);

my $Test  = Test::Builder->new;
my $updir = File::Spec->updir();

sub import {
    my $self   = shift;
    my $caller = caller;
    {
        no strict 'refs';
        *{$caller.'::eol_unix_ok'} = \&eol_unix_ok;
        *{$caller.'::all_perl_files_ok'} = \&all_perl_files_ok;
    }
    $Test->exported_to($caller);
    $Test->plan(@_);
}

sub _all_perl_files {
    my @all_files = _all_files(@_);
    return grep { _is_perl_module($_) || _is_perl_script($_) } @all_files;
}

sub _all_files {
    my @base_dirs = @_ ? @_ : File::Spec->catdir($Bin, $updir);
    my @found;
    my $want_sub = sub {
        return if ($File::Find::dir =~ m![\\/]?CVS[\\/]|[\\/]?.svn[\\/]!); # Filter out cvs or subversion dirs/
        return if ($File::Find::dir =~ m![\\/]?blib[\\/]libdoc$!); # Filter out pod doc in dist
        return if ($File::Find::dir =~ m![\\/]?blib[\\/]man\d$!); # Filter out pod doc in dist
        return if ($File::Find::name =~ m!Build$!i); # Filter out autogenerated Build script
        return unless (-f $File::Find::name && -r _);
        push @found, File::Spec->no_upwards( $File::Find::name );
    };
    my $find_arg = {
        %file_find_arg,
        wanted   => $want_sub,
        no_chdir => 1,
    };
    find( $find_arg, @base_dirs);
    return @found;
}

sub eol_unix_ok {
    my $file = shift;
    my $test_txt;
    $test_txt   = shift if !ref $_[0];
    $test_txt ||= "No windows line endings in '$file'";
    my $options = shift if ref $_[0] eq 'HASH';
    $options ||= {
        trailing_whitespace => 0,
    };
    $file = _module_to_path($file);
    open my $fh, $file or do { $Test->ok(0, $test_txt); $Test->diag("Could not open $file: $!"); return; };
    my $line = 0;
    while (<$fh>) {
        $line++;
        if (
           (!$options->{trailing_whitespace} && /\r$/) ||
           ( $options->{trailing_whitespace} && /(\r|[ \t]+)$/)
        ) {
          $Test->ok(0, $test_txt . " on line $line");
          return 0;
        }
    }
    $Test->ok(1, $test_txt);
    return 1;
}
sub all_perl_files_ok {
    my $options = shift if ref $_[0] eq 'HASH';
    my @files = _all_perl_files( @_ );
    _make_plan();
    foreach my $file ( @files ) {
      eol_unix_ok($file, $options);
    }
}

sub _is_perl_module {
    $_[0] =~ /\.pm$/i || $_[0] =~ /::/;
}

sub _is_perl_script {
    my $file = shift;
    return 1 if $file =~ /\.pl$/i;
    return 1 if $file =~ /\.t$/;
    open my $fh, $file or return;
    my $first = <$fh>;
    return 1 if defined $first && ($first =~ $PERL_PATTERN);
    return;
}

sub _module_to_path {
    my $file = shift;
    return $file unless ($file =~ /::/);
    my @parts = split /::/, $file;
    my $module = File::Spec->catfile(@parts) . '.pm';
    foreach my $dir (@INC) {
        my $candidate = File::Spec->catfile($dir, $module);
        next unless (-e $candidate && -f _ && -r _);
        return $candidate;
    }
    return $file;
}

sub _make_plan {
    unless ($Test->has_plan) {
        $Test->plan( 'no_plan' );
    }
    $Test->expected_tests;
}

sub _untaint {
    my @untainted = map { ($_ =~ $UNTAINT_PATTERN) } @_;
    return wantarray ? @untainted : $untainted[0];
}

1;
__END__

=head1 NAME

Test::EOL - Check the correct line endings in your project

=head1 SYNOPSIS

C<Test::EOL> lets you check the presence of windows line endings in your
perl code. It
report its results in standard C<Test::Simple> fashion:

  use Test::EOL tests => 1;
  eol_unix_ok( 'lib/Module.pm', 'Module is ^M free');

and to add checks for trailing whitespace:

  use Test::EOL tests => 1;
  eol_unix_ok( 'lib/Module.pm', 'Module is ^M and trailing whitespace free', { trailing_whitespace => 1 });

Module authors can include the following in a t/eol.t and have C<Test::EOL>
automatically find and check all perl files in a module distribution:

  use Test::EOL;
  all_perl_files_ok();

or

  use Test::EOL;
  all_perl_files_ok( @mydirs );

and if authors would like to check for trailing whitespace:

  use Test::EOL;
  all_perl_files_ok({ trailing_whitespace => 1 });

or

  use Test::EOL;
  all_perl_files_ok({ trailing_whitespace => 1 }, @mydirs );

=head1 DESCRIPTION

This module scans your project/distribution for any perl files (scripts,
modules, etc) for the presence of windows line endings.

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 all_perl_files_ok( [ \%options ], [ @directories ] )

Applies C<eol_unix_ok()> to all perl files found in C<@directories> (and sub
directories). If no <@directories> is given, the starting point is one level
above the current running script, that should cover all the files of a typical
CPAN distribution. A perl file is *.pl or *.pm or *.t or a file starting
with C<#!...perl>

If the test plan is defined:

  use Test::EOL tests => 3;
  all_perl_files_ok();

the total number of files tested must be specified.

=head2 eol_unix_ok( $file [, $text] [, \%options ]  )

Run a unix EOL check on C<$file>. For a module, the path (lib/My/Module.pm) or the
name (My::Module) can be both used.

=head1 AUTHOR

Tomas Doran (t0m) C<< <bobtfish@bobtfish.net> >>

=head1 BUGS

Testing for EOL styles other than unix (\n) currently unsupported.

The source code can be found on github, as listed in C< META.yml >,
patches are welcome.

Otherwise please report any bugs or feature requests to
C<bug-test-eol at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-EOL>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

Shamelessly ripped off from L<Test::NoTabs>.

=head1 SEE ALSO

L<Test::More>, L<Test::Pod>. L<Test::Distribution>, L<Test:NoWarnings>,
L<Test::NoTabs>, L<Module::Install::AuthorTests>.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Tomas Doran, some rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

