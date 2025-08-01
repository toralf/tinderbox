#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# print tinderbox statistics

function printImageName() {
  local img=${1?IMG MISSING}
  local chars=${2:-43}

  printf "%-${chars}s" $(cut -c -$chars <$img/var/tmp/tb/name)
}

function checkHistory() {
  local file=${1?FILE MISSING}
  local flag=${2?FLAG MISSING}

  # e.g.:
  # X = @x failed even to start
  # x = @x failed due to a package
  # . = never run before
  #   = no issues
  # ? = internal error
  if [[ -s $file ]]; then
    local line=$(tail -n 1 $file)
    if grep -q " NOT ok " <<<$line; then
      if grep -q " NOT ok $" <<<$line; then
        flags+="${flag,,}" # upper case
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

function printTimeDiff() {
  local ts=${1?TIME NOT GIVEN}

  set +e # "0" is valid compuation result here
  local delta
  ((delta = EPOCHSECONDS - ts))
  local second
  ((second = delta % 60))
  if [[ $delta -lt 60 ]]; then
    printf "       %2i " $second
  else
    local minute
    ((minute = delta / 60 % 60))
    if [[ $delta -lt 3600 ]]; then
      printf "    %2i:%02i " $minute $second
    else
      local hour
      ((hour = delta / 60 / 60))
      printf " %2i:%02i:%02i " $hour $minute $second
    fi
  fi
  set -e
}

# whatsup.sh -o
#   pkg fail bgo  day  done .1st .upd   todo lcx      12#12      Sat Dec 28 21:26:33 UTC 2024      35.13 33.27 32.92
#  6068  318  10  7.7  5817    -    -  10648 lc  ~/run/23.0-20241201-015002
#  2433   28   1  4.3   673    -  683  15770 lc  ~/run/23.0_desktop-20241204-113502
#  2183   25   -  2.1   657    -  144  15739 lc  ~/run/23.0_desktop-20241206-162002
function Overall() {
  local locked=$(wc -l < <(ls -d /run/tb/23.*.lock 2>/dev/null))
  local all=$(wc -w <<<$images)

  echo "  pkg fail bgo  day  done .1st .upd   todo lcx    $locked#$all    $(date)    $(grep 'procs_running' /proc/stat | cut -f 2 -d ' ')  $(cut -f 1-3 -d ' ' </proc/loadavg)"

  for i in $images; do
    local pkgs=$(grep -c ' ::: completed emerge' $i/var/log/emerge.log 2>/dev/null)
    # do not count "misc" findings
    local fail=$(grep -h -m 1 -c 'The build log matches a QA pattern' $i/var/tmp/tb/issues/*/comment0 2>/dev/null | grep -c '0')
    local bgo=$(wc -l < <(ls $i/var/tmp/tb/issues/*/.reported 2>/dev/null))
    local day=$(bc <<<"scale=2; ($EPOCHSECONDS - $(getStartTime $i)) / 86400.0" 2>/dev/null)
    local done=$(grep -c -v "^[#=@%]" $i/var/tmp/tb/task.history 2>/dev/null)
    local bl1=$(wc -l <$i/var/tmp/tb/backlog.1st)
    local blu=$(wc -l <$i/var/tmp/tb/backlog.upd)
    local bl=$(wc -l <$i/var/tmp/tb/backlog)

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
    elif __has_cgroup $i; then
      flags+="C"
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
    elif grep -q "^STOP" $i/var/tmp/tb/backlog{,.1st,.upd}; then
      flags+="s"
    elif grep -q "^INFO" $i/var/tmp/tb/backlog{,.1st,.upd}; then
      flags+="i"
    else
      flags+=" "
    fi

    local b=$(basename $i)
    # shellcheck disable=SC2088
    [[ -e ~tinderbox/run/$b ]] && d='~/run' || d='~/img'
    printf "%5i %4i %3i %4.1f %5i %4i %4i  %5i %3s %s/%s\n" ${pkgs:-0} ${fail:-0} $bgo ${day:-0} ${done:-0} ${bl1:-0} ${blu:-0} ${bl:-0} "$flags" $d $b | sed -e 's, 0 , - ,g'
  done
}

# whatsup.sh -t
#
# 23.0_desktop-20210102  0:19 m  dev-ros/message_to_tf
# 23.0_desktop_plasma_s  0:36 m  dev-perl/Module-Install
function Tasks() {
  for i in $images; do
    local taskfile=$i/var/tmp/tb/task
    if printImageName $i && ! __is_stopped $i && [[ -s $taskfile ]]; then

      printTimeDiff $(stat -c %Z $taskfile)
      local task=$(cat $taskfile)
      local line
      if [[ $task =~ "@" || $task =~ "%" || $task =~ "#" ]]; then
        line="$task"
      else
        line=" $task"
      fi
      cut -c 1-$((columns - 54)) <<<$line
    else
      echo
    fi
  done
}

# whatsup.sh -l
#
# 23.0_desktop_plasma_s  0:02 m  >>> AUTOCLEAN: media-sound/toolame:0
# 23.0_systemd-20210123  0:44 m  >>> (1 of 2) sci-libs/fcl-0.5.0
function LastEmergeOperation() {
  for i in $images; do
    if printImageName $i && ! __is_stopped $i; then
      read -r time line < <(tail -n 1 $i/var/log/emerge.log 2>/dev/null)
      if [[ -z $time ]]; then
        echo
        continue
      fi
      printTimeDiff $(cut -c 1-10 <<<$time)
      if [[ -f $i/var/tmp/tb/WAIT ]]; then
        echo -n "w"
      else
        echo -n " "
      fi
      cut -c 1-$((columns - 54)) < <(sed -e 's,::.*,,' -e 's,=== ,,' -e 's,>>> ,,' -e 's,\*\*\*.*,,' -e 's,AUTOCLEAN.*,,' -e 's,Compiling/Merging (,,' -e 's,Merging (,,' -e 's,Post-Build Cleaning (,,'  <<<$line)
    else
      echo
    fi
  done
}

# whatsup.sh -d
#                                                        0d   1d   2d   3d   4d   5d   6d   7d
# 23.0_no_multilib-j3_debug-20210620-175917            1704 1780 1236 1049 1049  727  454  789
# 23.0_desktop_systemd-j3_debug-20210620-181008        1537 1471 1091  920 1033  917  811  701´
function PackagesPerImagePerRunDay() {
  printf "%50s" ""
  local oldest=$(
    set -o pipefail
    sort -n ~tinderbox/run/*/var/tmp/tb/setup.timestamp 2>/dev/null | head -n 1
  )
  local days=$(((EPOCHSECONDS - ${oldest:-$EPOCHSECONDS}) / 86400))
  for i in $(seq 0 $days); do
    printf "%4id" $i
  done
  echo

  for i in $(list_images_by_age "run"); do
    if printImageName $i 50; then
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
# 12128 emerged packages under ~tinderbox/run in the past  8.6 days (63.7%)
# 16643 emerged packages under ~tinderbox/img in the past 52.0 days (87.5%)
function Coverage() {
  local tmpfile
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
  (
    cd /var/db/repos/gentoo
    ls -d *-*/* virtual/*
  ) | grep -v -F 'metadata.xml' | sort >$tmpfile

  local N=$(wc -l <$tmpfile)
  printf "%5i packages available in ::gentoo\n" $N

  for i in run img; do
    local emerged=~tinderbox/img/packages.$i.emerged.txt
    local not_emerged=~tinderbox/img/packages.$i.not_emerged.txt

    grep -H '::: completed emerge' ~tinderbox/$i/*/var/log/emerge.log 2>/dev/null |
      awk '{ print $8 }' |
      sort -u |
      tee ~tinderbox/img/packages-versions.$i.emerged.txt |
      xargs -r qatom -CF "%{CATEGORY}/%{PN}" |
      sort -u >$emerged

    # emerged + not_emerged != all e.g. due to unmerges
    diff $emerged $tmpfile | grep '>' | cut -f 2 -d ' ' -s >$not_emerged

    local n
    n=$(wc -l <$emerged)
    local oldest=$(sort -n ~tinderbox/$i/*/var/tmp/tb/setup.timestamp 2>/dev/null | head -n 1)
    local days=0
    if [[ -n $oldest ]]; then
      days=$(echo "scale=2.1; ($EPOCHSECONDS - $oldest) / 3600 / 24" | bc)
    fi
    local perc=0
    if [[ $N -gt 0 ]]; then
      perc=$(echo "scale=2.1; 100.0 * $n / $N" | bc)
    fi
    printf "%5i emerged packages under ~tinderbox/%s in the past %4.1f days (%4.1f%%)\n" $n $i $days $perc
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

      print " ", join (" ", grep { $max == $pet{$_} } sort keys %pet);
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
  columns=160
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
