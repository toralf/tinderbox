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
if sort -u ~tinderbox/img/*/var/tmp/sam.txt >$tmpfile 2>/dev/null; then
  cp $tmpfile ~tinderbox/img/sam.txt
fi
rm $tmpfile

# xgqt : big package size
#
if find ~tinderbox/img/*/var/tmp/xgqt.txt ! -wholename '*_test*' -exec cat {} + >$tmpfile 2>/dev/null; then
  perl -wane '
    chomp;
    next if ($#F != 2);
    my $u = $F[1];                 # unit (string)
    next unless ($u =~ m/GiB/);
    my $s = $F[0];                 # size (integer)
    my $p = $F[2];                 # package (string)
    $h{$p}->{$s} = 1 if ($s >= 4); # a hash is always uniq

    END {
      foreach my $p (sort keys %h) {
        printf "%-50s ", $p;
        foreach my $s (sort { $b <=> $a } keys %{$h{$p}}) {
          printf "%7.1f", $s;
        }
        print "\n";
      }
    }' <$tmpfile >~tinderbox/img/xgqt.txt
fi
rm $tmpfile

# sam_ + flow
#
(
  if [[ ${1-} == "reset" ]]; then
    find ~tinderbox/img/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2" 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r cat 2>/dev/null
  else
    cat ~tinderbox/img/needed.ELF.2.txt
    find ~tinderbox/run/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2" -cmin -65 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r cat 2>/dev/null
  fi
) | sort -u >$tmpfile
cp $tmpfile ~tinderbox/img/needed.ELF.2.txt
rm $tmpfile

(
  if [[ ${1-} == "reset" ]]; then
    find ~tinderbox/img/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED" 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r grep -H . 2>/dev/null |
      sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,'
  else
    cat ~tinderbox/img/needed.txt
    find ~tinderbox/run/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED" -cmin -65 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r grep -H . 2>/dev/null |
      sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,'
  fi
) | sort -u >$tmpfile
cp $tmpfile ~tinderbox/img/needed.txt
rm $tmpfile

# sam bashrc.clang hook
#
if [[ ${1-} == "reset" ]]; then
  opt="-c"
else
  opt="-r"
fi
tar $opt -f $tmpfile ~tinderbox/run/*/var/tmp/tb/issues/*/files/var.tmp.clang.tar.xz 2>/dev/null
cp $tmpfile ~tinderbox/img/all-var.tmp.clang.tar.xz.tar
rm $tmpfile
