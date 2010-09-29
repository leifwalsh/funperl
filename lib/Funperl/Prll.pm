#!/usr/bin/perl

package Funperl::Prll;

=pod

=head1 NAME

Funperl::Prll - Parallel execution, generator functions

=head1 SYNOPSIS

    use Funperl::Prll qw(:prll);

    my $cube_pid = pcall {
      for (1..1000000) {
        print $_ * $_ * $_, $/;
      }
    };

    my $net_pid = pexec("wget", "-Ogoogle.html", "www.google.com");

    pwait($cube_pid);
    pwait($net_pid);

    use Funperl::Prll qw(:gen);

    sub mygen(\&$) {
      my ($callback, $arg) = @_;
      my $ret = ...;
      for (some_function_of($arg)) {
        $callback->($ret);
      }
    }

    my @results = collect(\&mygen, $arg);

=head1 DESCRIPTION

Provides some utility functions for executing things in parallel, be they other
perl code or external programs, and some functions for callback-based data
pipeline programs.

=head1 FUNCTIONS

=cut

use warnings;
use strict;

use POSIX ":sys_wait_h";

use Funperl::Dbg qw(:printers);

our (@EXPORT_OK, %EXPORT_TAGS);
BEGIN {
  use Exporter qw(import);

  %EXPORT_TAGS = (prll => [qw(pcall pexec pcollect pwait pwaitall
                              pterm pkill ptermall pkillall)],
                  gen => [qw(collect pcollect collector)]);

  @EXPORT_OK = ();
  for my $vs (values(%EXPORT_TAGS)) {
    push(@EXPORT_OK, $_) for (@$vs);
  }
  $EXPORT_TAGS{all} = \@EXPORT_OK;
}

our %forked = ();

sub REAPER {
  my $child;
  while (($child = waitpid(-1,WNOHANG)) > 0) {
    $forked{$child} = 0;
  }
  $SIG{CHLD} = \&REAPER;
}
$SIG{CHLD} = \&REAPER;

=head2 PARALLEL EXECUTION

=over

=item C<pcall \&CODE[, @args]>

Executes a perl function in a new thread, and returns the pid of the forked
thread.  This function is the basis for all other parallel execution-style
functions here.

    my $pid = pcall {
        ...;  # code to be executed in a new thread goes here
      }, $arg1, $arg2;  # optional arguments for calling the CODE block

=cut

sub pcall(\&;@) {
  &tr_enter;

  my @args = @_;
  my $code = shift(@args);

  my $pid = fork();
  die("fork() unsuccessful: $!") unless (defined($pid));

  if ($pid == 0) {
    $code->(@args);
    exit(0);
  } else {
    dbg("forked child $pid");
    $forked{$pid} = 1;
  }

  tr_exit($pid);
}

=item C<pexec @cmd_list>

Executes an external program in a new thread, returns the pid of the forked
thread.

    my $pid = pexec("ls", "-l", "--color", "auto");

=cut

sub pexec(@) {
  &tr_enter;

  my @args = @_;
  my $pid = pcall {
    &tr_enter;
    dbg("child execing (", join(", ", @args), ")");
    exec(@args);
    tr_exit;
  };

  tr_exit($pid);
}

=item C<pwait $pid>

Waits on a forked thread, specified by pid.

=cut

sub pwait($) {
  &tr_enter;

  my ($victim) = @_;
  while ($forked{$victim}) {
    dbg("waiting on $victim...");
    $forked{$victim} = 0 if (waitpid($victim, WNOHANG) > 0);
  }
  dbg("$victim terminated");

  tr_exit($victim);
}

=item C<pwaitall>

Waits on all child threads that have been forked with this module.

=cut

sub pwaitall() {
  &tr_enter;

  for my $victim (keys(%forked)) {
    pwait($victim) if ($forked{$victim});
  }
  dbg("all child threads have ended");

  tr_exit;
}

=item C<pterm $pid>

Terminates a child thread, specified by pid (sends SIGTERM), and waits for it.

=cut

sub pterm($) {
  &tr_enter;

  my ($victim) = @_;

  if (kill TERM => $victim) {
    dbg("sent SIGTERM to $victim");
    pwait($victim);
    dbg("$victim died");
  } else {
    dbg("couldn't send SIGTERM to $victim, maybe it already died?");
  }

  tr_exit;
}

=item C<pkill $pid>

Kills a child thread, specified by pid (sends SIGKILL), and waits for it.

=cut

sub pkill($) {
  &tr_enter;

  my ($victim) = @_;

  if (kill KILL => $victim) {
    dbg("sent SIGKILL to $victim");
    pwait($victim);
    dbg("$victim died");
  } else {
    dbg("couldn't send SIGKILL to $victim, maybe it already died?");
  }

  tr_exit;
}

=item C<ptermall>

Terminates all child threads with SIGTERM.

=cut

sub ptermall() {
  &tr_enter;

  for my $victim (keys(%forked)) {
    pterm($victim) if ($forked{$victim});
  }
  dbg("all child threads terminated");

  tr_exit;
}

=item C<pkillall>

Kills all child threads with SIGKILL.

=cut

sub pkillall() {
  &tr_enter;

  for my $victim (keys(%forked)) {
    pkill($victim) if ($forked{$victim});
  }
  dbg("all child threads killed");

  tr_exit;
}

=back

=head2 GENERATOR FUNCTION UTILITIES

=over

=item C<collect \&CODE[, @args]>

Executes a generator function, and substitutes its own callback for that
generator function.  This callback collects its arguments in a single array, a
ref to which is returned.

This effectively turns a generator function into a straight function that
returns an array.  Maybe useful for testing?

    sub mygen(\&;@) {
      my $callback = $_[0];
      my $ret = ...;
      $callback->($ret);
    }

    my @results = collect(\&mygen, @args);

=cut

sub collect(\&;@) {
  &tr_enter;

  my @args = @_;
  my $code = shift(@args);

  my @ret = ();
  $code->(sub {
            &tr_enter;
            if (@_ == 1) {
              push(@ret, $_[0]);
            } else {
              my @item = @_;
              push(@ret, \@item);
            }
            tr_exit;
          }, @args);

  tr_exit(\@ret);
}

=item C<pcollect \&CODE[, @args]>

Executes a generator function in parallel, and substitutes its own callback for
that generator function.  This callback collects its arguments in a single
array, a ref to which is returned along with the pid of the parallel thread.

To use this, write a generator, then call C<pcollect> on it (with any arguments
you need).  You will be returned a pid to wait on, and an array ref you can
safely use after you've waited on that pid.

    sub mygen(\&;@) {
      my $callback = $_[0];
      my $ret = ...;
      $callback->($ret);
    }

    my ($pid, $results) = pcollect(\&mygen, @args);
    pwait($pid);
    process(@$results);

=cut

sub pcollect(\&;@) {
  &tr_enter;

  my @args = @_;
  my $code = shift(@args);

  my @ret = ();
  my $pid = pcall {
    &tr_enter;
    $code->(@args, sub {
              &tr_enter;
              if (@_ == 1) {
                push(@ret, $_[0]);
              } else {
                my @item = @_;
                push(@ret, \@item);
              }
              tr_exit;
            });
    tr_exit;
  };

  tr_exit($pid, \@ret);
}

=item C<collector \&CODE>

Same idea as C<collect> and C<pcollect>, except that instead of executing the
generator function, it just returns to you a new function which, when executed,
will return the array you'd get by using C<collect>.

So, simply, C<\&{collector(\&gen)}-E<gt>(@args)> is equivalent to
C<collect(\&gen, @args)>.  Just a matter of preference.

    my $regular_fn = collector sub {
        my $callback = $_[0];
        my $ret = ...;
        $callback->($ret);
      };

    my @results = $regular_fn->(@args);

=cut

sub collector(\&) {
  &tr_enter;
  my ($gen) = @_;
  tr_exit(sub {
            &tr_enter;
            my @args = @_;
            my @ret = ();
            $gen->(sub {
                     &tr_enter;
                     if (@_ == 1) {
                       push(@ret, $_[0]);
                     } else {
                       my @item = @_;
                       push(@ret, \@item);
                     }
                     tr_exit;
                   }, @args);
            tr_exit(@ret);
          });
};

1;

__END__

=pod

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
