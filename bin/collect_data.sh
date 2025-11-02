#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

# sam_ : bashrc meson hook
#
sort -u ~tinderbox/img/*/var/tmp/sam.txt >$tmpfile
chmod a+r $tmpfile
mv $tmpfile ~tinderbox/img/sam.txt

# xgqt : big package size
#
find ~tinderbox/img/*/var/tmp/big_packages.txt ! -wholename '*_test*' -exec cat {} + |
  perl -wane '
    chomp;
    next if ($#F != 2);
    my $u = $F[1];                 # unit (string)
    next unless ($u =~ m/GiB/);
    my $s = $F[0];                 # size (integer)
    my $p = $F[2];                 # package (string)
    $h{$p}->{$s} = 1 if ($s >= 4.0);

    END {
      foreach my $p (sort keys %h) {
        printf "%-50s ", $p;
        foreach my $s (sort { $b <=> $a } keys %{$h{$p}}) {
          printf "%7.1f", $s;
        }
        print "\n";
      }
    }' >$tmpfile
chmod a+r $tmpfile
mv $tmpfile ~tinderbox/img/big_packages.txt

# sam_ + flow
#
{
  if [[ ${1-} == "reset" ]]; then
    find ~tinderbox/img/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2"
  else
    echo ~tinderbox/img/needed.ELF.2.txt
    find ~tinderbox/run/*/var/db/pkg/ -ignore_readdir_race -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2" -cmin -65
  fi
} |
  grep -v -F '/-MERGING-' |
  xargs -r cat |
  sort -u >$tmpfile
chmod a+r $tmpfile
mv $tmpfile ~tinderbox/img/needed.ELF.2.txt

{
  if [[ ${1-} == "reset" ]]; then
    find ~tinderbox/img/*/var/db/pkg/ -ignore_readdir_race -mindepth 3 -maxdepth 4 -name "NEEDED" |
      grep -v -F '/-MERGING-' |
      xargs -r grep -H . |
      sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,'
  else
    cat ~tinderbox/img/needed.txt
    find ~tinderbox/run/*/var/db/pkg/ -ignore_readdir_race -mindepth 3 -maxdepth 4 -name "NEEDED" -cmin -65 |
      grep -v -F '/-MERGING-' |
      xargs -r grep -H . |
      sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,'
  fi
} | sort -u >$tmpfile
chmod a+r $tmpfile
mv $tmpfile ~tinderbox/img/needed.txt
