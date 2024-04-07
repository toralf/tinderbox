#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# print tinderbox statistics

function printImageName() {
  if [[ -s $1/var/tmp/tb/name ]]; then
    local chars=${2:-42}
    printf "%-${chars}s" $(cut -c -${chars} <$1/var/tmp/tb/name)
  else
    return 1
  fi
}

function check_history() {
  local file=$1
  local flag=$2

  # e.g.:
  # X = @x failed even to start
  # x = @x failed due to a package
  # . = never run before
  #   = no issues
  # ? = internal error
  if [[ -s $file ]]; then
    local line
    line=$(tail -n 1 $file)
    if grep -q " NOT ok " <<<$line; then
      if grep -q " NOT ok $" <<<$line; then
        local uflag
        uflag=${flag,,}
        flags+="$uflag"
      else
        flags+="$flag"
      fi
    elif grep -q " ok$" <<<$line; then
      flags+=" "
    else
      flags+="?"
    fi
  else
    flags+="."
  fi
}

# whatsup.sh -o
#
# compl fail bgo  day backlog .upd .1st lck 11#11 locked  +++  Fri Apr  5 19:37:03 UTC 2024
#  7188   95   1  6.6   12348   75    - lc  ~/run/23.0_desktop_gnome-20240330-044003
#   171    1   -  0.2   16968    -    2 lc  ~/run/23.0_desktop_gnome-20240405-154537
function Overall() {
  local locked
  locked=$(wc -l < <(ls -d /run/tb/[12]?.*.lock 2>/dev/null))
  local all=$(wc -w <<<$images)
  echo "compl fail bgo  day backlog .upd .1st lck $locked#$all locked  +++  $(date)"

  for i in $images; do
    local compl=$(grep -c ' ::: completed emerge' $i/var/log/emerge.log 2>/dev/null)
    local fail=$(ls -1 $i/var/tmp/tb/issues 2>/dev/null | xargs -r -n 1 basename | cut -f 3- -d '-' -s | sort -u | wc -w)
    local bgo=$(wc -l < <(ls $i/var/tmp/tb/issues/*/.reported 2>/dev/null) || echo "0")
    local days=$(bc <<<"scale=2; ($EPOCHSECONDS - $(getStartTime $i)) / 86400.0")
    local bl=$(wc -l <$i/var/tmp/tb/backlog 2>/dev/null || echo "0")
    local bl1=$(wc -l <$i/var/tmp/tb/backlog.1st 2>/dev/null || echo "0")
    local blu=$(wc -l <$i/var/tmp/tb/backlog.upd 2>/dev/null || echo "0")

    # "l" image is locked
    # "c" image is under cgroup control
    local flags=""
    if __is_locked $i; then
      flags+="l"
    else
      flags+=" "
    fi
    if __is_cgrouped $i; then
      flags+="c"
    else
      flags+=" "
    fi

    # stop/replace state
    if [[ -f $i/var/tmp/tb/KEEP ]]; then
      flags+="K"
    elif [[ -f $i/var/tmp/tb/EOL ]]; then
      flags+="E"
    elif [[ -f $i/var/tmp/tb/STOP ]]; then
      flags+="S"
    elif grep -q "^STOP" $i/var/tmp/tb/backlog*; then
      flags+="s"
    elif grep -q "^INFO" $i/var/tmp/tb/backlog*; then
      flags+="i"
    else
      flags+=" "
    fi

    local b=$(basename $i)
    # shellcheck disable=SC2088
    [[ -e ~tinderbox/run/$b ]] && d='~/run' || d='~/img'
    printf "%5s %4s %3s %4.1f %7s %4s %4s %3s %s/%s\n" $compl $fail $bgo $days $bl $blu $bl1 "$flags" "$d" "$b" | sed -e 's, 0 , - ,g'
  done
}

# whatsup.sh -t
#
# 17.1_desktop-20210102  0:19 m  dev-ros/message_to_tf
# 17.1_desktop_plasma_s  0:36 m  dev-perl/Module-Install
function Tasks() {
  for i in $images; do
    local tsk=$i/var/tmp/tb/task
    if printImageName $i && ! __is_stopped $i && [[ -s $tsk ]]; then
      local task=$(cat $tsk)

      set +e
      ((delta = EPOCHSECONDS - $(stat -c %Z $tsk)))
      ((minutes = delta / 60 % 60))
      if [[ $delta -lt 3600 ]]; then
        ((seconds = delta % 60))
        printf "%3i:%02i m " $minutes $seconds
      else
        ((hours = delta / 3600))
        printf "%3i:%02i h " $hours $minutes
      fi
      set -e

      if [[ ! $task =~ "@" && ! $task =~ "%" && ! $task =~ "#" ]]; then
        echo -n " "
      fi

      if [[ ${#task} -gt $((columns - 58)) ]]; then
        echo "$(cut -c1-$((columns - 55)) <<<$task)..."
      else
        echo $task
      fi
    else
      echo
    fi
  done
}

# whatsup.sh -l
#
# 17.1_desktop_plasma_s  0:02 m  >>> AUTOCLEAN: media-sound/toolame:0
# 17.1_systemd-20210123  0:44 m  >>> (1 of 2) sci-libs/fcl-0.5.0
function LastEmergeOperation() {
  for i in $images; do
    if printImageName $i && ! __is_stopped $i && [[ -s $i/var/log/emerge.log ]]; then
      tail -n 1 $i/var/log/emerge.log |
        sed -e 's,::.*,,' -e 's,Compiling/,,' -e 's,Merging (,,' -e 's,\*\*\*.*,,' |
        perl -wane '
        chop ($F[0]);
        my $delta = time() - $F[0];
        my $minutes = $delta / 60 % 60;
        if ($delta < 3600) {
          my $seconds = $delta % 60;
          printf (" %2i:%02i m ", $minutes, $seconds);
        } else  {
          my $hours = $delta / 3600;
          printf (" %2i:%02i h%s", $hours, $minutes, $delta < 3*3600 ? " " : "!"); # mark too long emerge run times
        }
        if (-f "'$i'/var/tmp/tb/WAIT") {
          printf ("W");
        } else {
          printf (" ");
        }
        my $line = join (" ", @F[2..$#F]);
        print substr ($line, 0, '$columns' - 38), "\n";
      '
    else
      echo
    fi
  done
}

# whatsup.sh -d
#                                                        0d   1d   2d   3d   4d   5d   6d   7d
# 17.1_no_multilib-j3_debug-20210620-175917            1704 1780 1236 1049 1049  727  454  789
# 17.1_desktop_systemd-j3_debug-20210620-181008        1537 1471 1091  920 1033  917  811  701´
function PackagesPerImagePerRunDay() {
  printf "%57s" ""
  local oldest=$(
    set -o pipefail
    sort -n ~tinderbox/run/*/var/tmp/tb/setup.timestamp | head -n 1
  )
  local days=$(((EPOCHSECONDS - ${oldest:-$EPOCHSECONDS}) / 86400))
  for i in $(seq 0 $days); do
    printf "%4id" $i
  done
  echo

  for i in $(list_images_by_age "run"); do
    if printImageName $i 57; then
      local start_time
      start_time=$(getStartTime $i)
      perl -F: -wane '
        BEGIN {
          @packages = (); # emerges per runday
        }

        my $epoch_time = $F[0];
        next unless (m/::: completed emerge/);
        my $rundays = int( ($epoch_time - '$start_time') / 86400);
        $packages[$rundays]++;

        END {
          if ($#packages >= 0) {
            foreach my $rundays (0..$#packages) {
              ($packages[$rundays]) ? printf "%5i", $packages[$rundays] : printf "    -";
            }
          }
          print "\n";
        }
      ' $i/var/log/emerge.log
    else
      echo
    fi
  done
}

# whatsup.sh -c
#
# 19025 packages available in ::gentoo
# 12128 emerged packages under ~tinderbox/run in the last  8.6 days (63.7%)
# 16643 emerged packages under ~tinderbox/img in the last 52.0 days (87.5%)
function Coverage() {
  local tmpfile
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
  (
    cd /var/db/repos/gentoo
    ls -d *-*/* virtual/*
  ) | grep -v -F 'metadata.xml' | sort >$tmpfile

  local N
  N=$(wc -l <$tmpfile)
  printf "%5i packages available in ::gentoo\n" $N

  for i in run img; do
    local emerged=~tinderbox/img/packages.$i.emerged.txt
    local not_emerged=~tinderbox/img/packages.$i.not_emerged.txt

    grep -H '::: completed emerge' ~tinderbox/$i/*/var/log/emerge.log 2>/dev/null |
      awk '{ print $8 }' |
      sort -u |
      tee ~tinderbox/img/packages-versions.$i.emerged.txt |
      xargs -r qatom -F "%{CATEGORY}/%{PN}" |
      sort -u >$emerged

    # emerged + not_emerged != all e.g. due to unmerges
    diff $emerged $tmpfile | grep '>' | cut -f 2 -d ' ' -s >$not_emerged

    local n
    n=$(wc -l <$emerged)
    local oldest=$(sort -n ~tinderbox/$i/*/var/tmp/tb/setup.timestamp 2>/dev/null | head -n 1)
    local days=0
    if [[ -n $oldest ]]; then
      days=$(echo "scale=2.1; ($EPOCHSECONDS.0 - $oldest) / 3600 / 24" | bc)
    fi
    local perc=0
    if [[ $N -gt 0 ]]; then
      perc=$(echo "scale=2.1; 100.0 * $n / $N" | bc)
    fi
    printf "%5i emerged packages under ~tinderbox/%s in the last %4.1f days (%4.1f%%)\n" $n $i $days $perc
  done

  rm $tmpfile
}

# whatsup.sh -p
#
# package (revisions) x emerges in ~/run
#  2477x1 3163x2 3176x3 2548x4 1577x5 1059x6 718x7 454x8 353x9 448x10 437x11 126x12 86x13 21x14 9x15 12x16 25x17 17x18 2x19 1x26 dev-vcs/git-2.35.1
#
#  16709 package (revisions) in 67930 emerges
function CountEmergesPerPackages() {
  echo "package (revisions) x emerges in ~/run"

  perl -wane '
    BEGIN {
      my %pet = (); # package => emerges
    }

    next unless (m/::: completed emerge/);
    my $pkg = $F[7];
    $pet{$pkg}++;

    END {
      my %h = (); # pet => occurrence

      for my $key (sort keys %pet)  {
        my $value = $pet{$key};
        $h{$value}++;
      }

      my $total = 0; # total amount of emerge operations
      my $seen = 0;  # "     "      "  packages
      my $max = 0;   # emerges of a package

      for my $key (sort { $a <=> $b } keys %h)  {
        my $value = $h{$key};
        $seen += $value;
        $total += $key * $value;
        print " ", $value, "x", $key;
        $max = $key if ($max < $key);
      }

      for my $key (sort keys %pet)  {
        print " ", $key if ($max == $pet{$key});
      }
      print "\n\n $seen package (revisions) in $total emerges\n";
    }
  ' $(ls ~tinderbox/run/*/var/log/emerge.log 2>/dev/null)
}

#############################################################################
set -eu
export LANG=C.utf8
unset LC_TIME
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

source $(dirname $0)/lib.sh

if ! columns=$(tput cols 2>/dev/null); then
  columns=120
fi

while getopts cdlopt opt; do
  images=$(list_active_images)
  case $opt in
  c) Coverage ;;
  d) PackagesPerImagePerRunDay ;;
  l) LastEmergeOperation ;;
  o) Overall ;;
  p) CountEmergesPerPackages ;;
  t) Tasks ;;
  *)
    echo "unknown parameter '$opt'"
    exit 1
    ;;
  esac
  echo
done
