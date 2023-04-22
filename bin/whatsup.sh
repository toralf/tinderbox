#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# print tinderbox statistics

function PrintImageName() {
  local chars=${2:-42}
  printf "%-${chars}s" $(cut -c-${chars} <$1/var/tmp/tb/name 2>/dev/null)
}

function check_history() {
  local file=$1
  local flag=$2

  # eg.:
  # X = @x failed even to start
  # x = @x failed due to a package
  # . = never run before
  #   = no issues
  # ? = internal error
  if [[ -s $file ]]; then
    local line=$(tail -n 1 $file)
    if grep -q " NOT ok " <<<$line; then
      if grep -q " NOT ok $" <<<$line; then
        local uflag=$(tr '[:lower:]' '[:upper:]' <<<$flag)
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
# compl fail new day backlog .upd .1st wp rls 7#7 locked
#  4402   36   1 4.8   16529    7    0 W  r   ~/run/17.1-20210306-163653
#  4042   26   0 5.1   17774   12    2    r   ~/run/17.1_desktop_gnome-20210306-091529
function Overall() {
  local locked=$(ls -d /run/tinderbox/*.lock 2>/dev/null | wc -l)
  local all=$(wc -w <<<$images)
  echo "compl fail new  day backlog .upd .1st wp cls $locked#$all locked"

  for i in $images; do
    local days=$(bc <<<"scale=1; ( $EPOCHSECONDS - $(__getStartTime $i) ) / 86400.0")
    local bgo=$(
      set +f
      ls $i/var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l
    )

    local compl=0
    if ! compl=$(grep -c ' ::: completed emerge' $i/var/log/emerge.log 2>/dev/null); then
      compl=0
    fi

    # count emerge failures based on distinct package name+version+release
    # example of an issue directory name: 20200313-044024-net-analyzer_iptraf-ng-1.1.4-r3
    local fail=0
    if [[ -d $i/var/tmp/tb/issues ]]; then
      fail=$(ls -1 $i/var/tmp/tb/issues | while read -r j; do basename $j; done | cut -f3- -d'-' -s | sort -u | wc -w)
    fi

    local bl=$(wc -l 2>/dev/null <$i/var/tmp/tb/backlog || echo 0)
    local bl1=$(wc -l 2>/dev/null <$i/var/tmp/tb/backlog.1st || echo 0)
    local blu=$(wc -l 2>/dev/null <$i/var/tmp/tb/backlog.upd || echo 0)

    # "r" image is in ~rrunning
    # "l" image is locked
    local flags=""

    # result of last run of @world and @preserved-rebuild respectively:
    #
    # upper case: an error occurred
    # lower case: just a package failed
    # "." not yet run
    # " " ok
    check_history $i/var/tmp/tb/@world.history w
    check_history $i/var/tmp/tb/@preserved-rebuild.history p
    flags+=" "
    if __is_cgrouped $i; then
      flags+="c"
    else
      flags+=" "
    fi
    if __is_locked $i; then
      flags+="l"
    else
      flags+=" "
    fi

    # stop/replace state
    if [[ -f $i/var/tmp/tb/EOL ]]; then
      flags+="E"
    elif grep -q "^EOL" $i/var/tmp/tb/backlog* 2>/dev/null; then
      flags+="e"
    elif [[ -f $i/var/tmp/tb/STOP ]]; then
      flags+="S"
    elif grep -q "^STOP" $i/var/tmp/tb/backlog* 2>/dev/null; then
      flags+="s"
    elif grep -q "^INFO" $i/var/tmp/tb/backlog* 2>/dev/null; then
      flags+="i"
    else
      flags+=" "
    fi

    # images during setup are not yet symlinked to ~tinderbox/run
    local b=$(basename $i)
    # shellcheck disable=SC2088
    [[ -e ~tinderbox/run/$b ]] && d='~/run' || d='~/img' # shorten output
    printf "%5i %4i %3i %4.1f %7i %4i %4i %5s %s/%s\n" $compl $fail $bgo $days $bl $blu $bl1 "$flags" "$d" "$b" 2>/dev/null
  done
}

# whatsup.sh -t
# 17.1_desktop-20210102  0:19 m  dev-ros/message_to_tf
# 17.1_desktop_plasma_s  0:36 m  dev-perl/Module-Install
function Tasks() {
  for i in $images; do
    local tsk=$i/var/tmp/tb/task
    if PrintImageName $i && __is_running $i && [[ -s $tsk ]]; then
      local task=$(cat $tsk)

      set +e # integer calculation result could be 0
      ((delta = EPOCHSECONDS - $(stat -c %Y $tsk)))
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
    if PrintImageName $i && __is_running $i && [[ -s $i/var/log/emerge.log ]]; then
      tail -n 1 $i/var/log/emerge.log |
        sed -e 's,::.*,,g' -e 's,Compiling/,,' -e 's,Merging (,,' -e 's,\*\*\*.*,,' |
        perl -wane '
        chop ($F[0]);
        my $delta = time() - $F[0];
        if ($delta < 0) {
          # scary but needed
          $delta=0;
        }
        my $minutes = $delta / 60 % 60;
        if ($delta < 3600) {
          my $seconds = $delta % 60;
          printf (" %2i:%02i m  ", $minutes, $seconds);
        } else  {
          my $hours = $delta / 3600;
          printf (" %2i:%02i h%s ", $hours, $minutes, $delta < 7200 ? " " : "!");    # (exclamation) mark long runtimes
        }
        my $line = join (" ", @F[2..$#F]);
        print substr ($line, 0, '"'$((columns - 38))'"'), "\n";
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
  local max=$((($(date +%s) - $(cat ~tinderbox/run/*/var/tmp/tb/setup.timestamp | sort -n | head -n 1)) / 86400))
  for i in $(seq 0 $max); do
    printf "%4id" $i
  done
  echo

  for i in $(ls -d ~tinderbox/run/* 2>/dev/null | sort -t '-' -k 3); do
    if PrintImageName $i 57; then
      local start_time=$(__getStartTime $i)
      perl -F: -wane '
        BEGIN {
          @packages   = ();  # helds the amount of emerge operations per runday
        }

        my $epoch_time = $F[0];
        next unless (m/::: completed emerge/);

        my $rundays = int( ($epoch_time - '$start_time') / 86400);
        $packages[$rundays]++;

        END {
          if ($#packages >= 0) {
            $packages[$rundays] += 0;     # implicit initialize elements which are not already set
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

function getCoveredPackages() {
  grep -H '::: completed emerge' ~tinderbox/$1/*/var/log/emerge.log 2>/dev/null |
    # handle ::local
    tr -d ':' |
    awk '{ print $7 }' |
    xargs --no-run-if-empty qatom -F "%{CATEGORY}/%{PN}" |
    sort -u
}

#  whatsup.sh -c
# 19506 packages available in ::gentoo
# 16081 packages emerged under ~tinderbox/run   (82% for last 10 days)
# 17835 packages emerged under ~tinderbox/img   (91% for last 55 days)
function Coverage() {
  local all=$(mktemp /tmp/$(basename $0)_XXXXXX.all)
  (
    cd /var/db/repos/gentoo
    ls -d *-*/*
    ls -d virtual/*
  ) | grep -v -F 'metadata.xml' | sort >$all
  local N=$(wc -l <$all)
  printf "%5i packages available in ::gentoo\n" $N

  for i in run img; do
    local covered=~tinderbox/img/packages.$i.covered.txt
    local uncovered=~tinderbox/img/packages.$i.uncovered.txt # used in index.sh

    getCoveredPackages $i >$covered
    diff $covered $all | grep -F '>' | cut -f2 -d' ' -s >$uncovered

    local n=$(wc -l <$covered)
    local oldest=$(cat ~tinderbox/$i/??.*/var/tmp/tb/setup.timestamp 2>/dev/null | sort -n | head -n 1)
    local days=0
    if [[ -n $oldest ]]; then
      days=$(echo "scale=2.1; ($EPOCHSECONDS - $oldest) / 3600 / 24" | bc)
    fi
    local perc=0
    if [[ $N -gt 0 ]]; then
      perc=$(echo "scale=2.1; 100.0 * $n / $N" | bc)
    fi
    printf "%5i packages emerged under ~tinderbox/%s   (%3.1f%% for last %3.1f days)\n" $n $i $perc $days
  done

  rm $all
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
      my %pet = ();     # package => emerges
    }

    next unless (m/::: completed emerge/);

    my $pkg = $F[7];
    $pet{$pkg}++;

    END {
      my %h = ();       # pet => occurrence

      for my $key (sort keys %pet)  {
        my $value = $pet{$key};
        $h{$value}++;
      }

      my $total = 0;    # total amount of emerge operations
      my $seen = 0;     # "     "      "  packages
      my $max = 0;      # emerges of a package

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

# whatsup.sh -e
# yyyy-mm-dd   sum   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22  23
#
# 2021-04-31    15   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0  15   0   0   0
# 2021-05-01  2790  28  87  91  41   4  13   0   1  15  29  78  35  62  46  75   9   0 193 104 234 490 508 459 188
function emergeThruput() {
  echo -n "yyyy-mm-dd   sum  "
  for i in {0..23}; do
    printf "  %2i" $i
  done
  echo -e "\n"

  perl -F: -wane '
    BEGIN {
      my %Days = ();
    }
    {
      next unless (m/::: completed emerge/);

      my $epoch_time = $F[0];
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch_time);
      $year += 1900;
      $mon += 1;
      $mon = "0" . $mon if ($mon < 10);
      $mday = "0" . $mday if ($mday < 10);

      my $day = $year . "-" . $mon . "-" . $mday;
      $Days{$day}->{$hour}++;
      $Days{$day}->{"sum"}++;
    }

    END {
      my %Mean = ();

      # delete anything in %Days older 2 weeks b/c those values might be incomplete
      # due to house kept images having no reported bugs
      my ($youngest, $oldest) = (sort { $b cmp $a } keys %Days)[0,14];

      foreach my $key (keys %Days) {
        delete ($Days{$key}) if ($key lt $oldest);
      }

      # print out the daily values and calculate the mean of them
      for my $day (sort { $a cmp $b } keys %Days)  {
        my $value = $Days{$day}->{"sum"};
        printf("%-10s %5i  ", $day, $value);
        $Mean{"sum"} += $value if ($day ne $youngest);

        foreach my $hour (0..23) {
          $value = $Days{$day}->{$hour} ? $Days{$day}->{$hour} : 0;
          printf("%4i", $value);
          $Mean{$hour} += $value if ($day ne $youngest);
        }
        print "\n";
      }
      print "\n";

      # print out the mean values
      my $n = (scalar keys %Days) - 1;
      foreach my $key (keys %Mean)  {
        $Mean{$key} /= $n;
      }
      printf("%-10s %5i  ", "14d-mean", $Mean{"sum"});
      foreach my $hour (0..23) {
        printf("%4i", $Mean{$hour});
      }
      print "\n";
    }
  ' $(find ~tinderbox/img/*/var/log/emerge.log -mtime -15 | sort -t '-' -k 3)
}

#############################################################################
#
# main
#
set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8
unset LC_TIME

source $(dirname $0)/lib.sh

if ! columns=$(tput cols 2>/dev/null); then
  columns=120
fi

while getopts cdelopt opt; do
  images=$(list_images)
  case $opt in
  c) Coverage ;;
  d) PackagesPerImagePerRunDay ;;
  e) emergeThruput ;;
  l) LastEmergeOperation ;;
  o) Overall ;;
  p) CountEmergesPerPackages ;;
  t) Tasks ;;
  *)
    echo "unknown parameter '${opt}'"
    exit 1
    ;;
  esac
  echo
done
