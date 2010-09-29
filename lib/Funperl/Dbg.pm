#!/usr/bin/perl

package Funperl::Dbg;

=pod

=head1 NAME

Funperl::Dbg - Some simple debugging aids

=head1 SYNOPSIS

    use Funperl::Dbg qw(:all);
    debug(1);  # turn on debugging (and tracing and verbosity)
    
    sub myfn($$) {
      &tr_enter;
      my ($v1, $v2) = shift;
      @rets = ...;
      vrb("done calculating rets");
      dbg("received the following error codes: $some $other $stuff");
      return tr_exit(@ret);
    }

=head1 DESCRIPTION

Provides some quick and dirty functions for inserting removable debugging
statements and for controlling verbosity, as well as a facility for printing
function stacks in a nice way.

=head1 FUNCTIONS

=cut

use warnings;
use strict;

our (@EXPORT_OK, %EXPORT_TAGS);
BEGIN {
  use Exporter qw(import);

  %EXPORT_TAGS = (printers => [qw(dbg vrb tr_enter tr_exit)],
                  flags => [qw(debug verbose trace)]);

  @EXPORT_OK = ();
  for my $vs (values(%EXPORT_TAGS)) {
    push(@EXPORT_OK, $_) for (@$vs);
  }
  $EXPORT_TAGS{all} = \@EXPORT_OK;
}

our $debug = 0;

=head2 DEBUGGING

=over

=item C<debug [$flag]>

Called with a parameter, sets the debug flag to that parameter (as in
C<debug(1)>).  Without a parameter (actually either way), returns the value of
the debug flag.

=cut

sub debug(;$) {
  $debug = shift if (@_ == 1);
  $debug;
}

=item C<dbg $things, $to, $print>

If the debug flag is on, prints its arguments after printing C<"DEBUG: ">, and
follows it all with a newline.

=back

=cut

sub dbg(@) {
  print STDERR "DEBUG: ", @_, $/ if (debug());
}

our $verbose = 0;

=head2 VERBOSITY

=over

=item C<verbose [$flag]>

Called with a parameter, sets the verbose flag to that parameter (as in
C<verbose(1)>).  Without a parameter (actually either way), returns the value of
the verbose flag.

=cut

sub verbose(;$) {
  $verbose = shift if (@_ == 1);
  $verbose || $debug;
}

=item C<vrb $things, $to, $print>

If the verbose flag is on, prints its arguments.

=back

=cut

sub vrb(@) {
  print @_ if (verbose());
}

our $trace = 0;

=head2 STACK TRACING

=over

=item C<trace [$flag]>

Called with a parameter, sets the trace flag to that parameter (as in
C<trace(1)>).  Without a parameter (actually either way), returns the value of
the trace flag.

=cut

sub trace(;$) {
  $trace = shift if (@_ == 1);
  $trace || $debug;
}

our $stacklevel = 0;

=item C<tr_enter>

Prints the current line, file, package, and function name of the function being
entered, as well as any parameters to the function.

Uses an arcane "feature" of the C<&fun;> calling convention, so you should just
add C<&tr_enter;> to the beginning of every function you write, with no changes.
Try to do your best not to modify C<@_> with C<push> or C<pop> or C<shift> or
anything, too.

If you want to control which of the arguments are printed, you can pass them as
arguments to C<tr_enter>, but this is unmaintainable and not recommended.

For example:

    sub myfn {
      &tr_enter;
      my ($var) = @_;
      ...;
    }

=cut

sub tr_enter {
  my @stack = caller(1);
  $stacklevel++;
  print STDERR "TRACE: ", $stack[1], ":", $stack[2], " ", ">" x $stacklevel,
    $stack[0], "::", $stack[3], "(", join(", ", @_), ")", $/ if (trace());
}

=item C<tr_exit [$return[, $values]]>

Prints the current line, file, package, and function name of the function being
left, as well as any return value(s) from the function, if you pass them in.

Also returns any return values, and properly checks your function's
C<wantarray>, so feel free to use it between a C<return> and the return values,
or simply use the implicit return as in the second example below.

For example:

    sub my_mult_valued_fn {
      ...;
      return tr_exit($retval1, $retval2);
    }

    sub myfn {
      ...;
      tr_exit($ret);
    }

=cut

sub tr_exit {
  my @stack = caller(1);
  print STDERR "TRACE: ", $stack[1], ":", $stack[2], " ", "<" x $stacklevel,
    $stack[0], "::", $stack[3], " = ",
      ((@_ > 0) ? "nil" : "(" . join(", ", @_) . ")"), $/ if (trace());
  $stacklevel--;
  return $stack[5] ? @_ : $_[0];
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright 2010 Leif Walsh <leif.walsh@gmail.com>.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the <organization> nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
