#!/bin/sh
#
#set -x

# quick & dirty stats
#

# all active | running images
#
function list_images() {
  (
    cd ~;
    ls -1d run/* | xargs -n1 readlink | cut -f2- -d'/'
    df -h | grep 'img./' | cut -f4-5 -d'/'
  ) | sort -u
}


# gives sth. like:
#
# emerged failed  days    backlog rate    ~/run   locked
# 5567    91      8.6     14005   580     yes     yes     13.0-no-multilib-libressl-unstable_20170122-225602
# 1286    13      1.2     18641   299     yes     yes     13.0-systemd-libressl-unstable_20170130-102323
# 5537    75      8.2     15200   463     yes     yes     13.0-unstable_20170123-090431
# 6711    75      10.0    10090   891     yes     yes     desktop-stable_20170121-152726
#
function Overall() {
  echo "emerged failed  days    backlog rate    ~/run   locked"
  for i in $images
  do
    log=$i/var/log/emerge.log
    emerged=$(qlop -lC -f $log | wc -l)
    failed=$(ls -1 $i/tmp/issues 2>/dev/null | xargs -n 1 basename 2>/dev/null | cut -f2- -d'_' | sort -u | wc -w)
    days=$(echo "scale=1; ($(tail -n1 $log | cut -c1-10) - $(head -n1 $log | cut -c1-10)) / 86400" | bc)
    backlog=$(wc -l < $i/tmp/packages)
    rate=$(echo "(19000 - $backlog) / $days" | bc 2>/dev/null)
    if [[ $rate -le 0 || $rate -gt 1500 ]]; then
      rate='-'
    fi
    if [[ -e ~/run/$(basename $i) ]]; then
      run="yes"
    else
      run=""
    fi
    if [[ -f ~/$i/tmp/LOCK ]]; then
      lock="yes"
    else
      lock=""
    fi

    echo -e "$emerged\t$failed\t$days\t$backlog\t$rate\t$run\t$lock\t$(basename $i)"
  done
}


# gives sth. like:
#
# 13.0-libressl-unstable_20170110-100022            13:59:12 *** media-gfx/pictureflow
# 13.0-systemd-unstable_20170111-105830             13:54:54 >>> (4 of 4) games-server/cyphesis-0.6.2-r1
# 13.0-unstable_20170109-235418                     13:53:24 *** www-apps/chromedriver-bin
#
function LastEmergeOperation()  {
  for i in $images
  do
    printf "%s\r\t\t\t\t\t\t  " $(basename $i)
    tac ~/$i/var/log/emerge.log |\
    grep -m 1 -e "[>>>|***] emerge" |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' |\
    perl -wane '
      chop ($F[0]);
      my @t = split (/\s+/, scalar localtime ($F[0]));
      print join (" ", $t[3], @F[1,3..$#F]), "\n";
    '
  done
}


# gives sth. like:
#
# 13.0-libressl-unstable_20170110-100022            410 1244 1068  821  510  645  485  510  260
# 13.0-systemd-unstable_20170111-105830             545  681 1115  679  775  625  507  332
# 13.0-unstable_20170109-235418                      14  896 1029  813  551  438  618  625  416  304
#
function PackagesPerDay() {
  for i in $images
  do
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    qlop -lC -f $i/var/log/emerge.log |\
    perl -wane '
      BEGIN {
        %h   = ();
        $sum = 0;
        $day = 0;
        $old = "";
      }
      {
        $sum++;
        my $cur = $F[2];
        if ($old ne $cur) {
          $old = $cur;
          $day++;
        }
        $h{$day}++;
      }
      END {
        foreach my $k (sort { $a <=> $b } keys %h) {
          printf ("%5i", $h{$k});
        }
      }
    '
    echo " "
  done
}


# gives sth. like:
#
# 13.0-no-multilib-libressl-unstable_20170122-2256  Feb  1 11:15:48  dev-python/coloredlogs
# 13.0-systemd-libressl-unstable_20170130-102323
# 13.0-unstable_20170123-090431                     Feb  1 11:13:31  dev-java/dtdparser
#
function CurrentTask()  {
  for i in $images
  do
    printf "%s\r\t\t\t\t\t\t  " $(basename $i)
    cat $i/tmp/task 2>/dev/null || echo
  done
}


#######################################################################
#
images=$(list_images)

echo
echo "$(echo $images | wc -w) images ($(ls ~/img? | wc -w) at all) :"

while getopts hlopt\? opt
do
  echo
  case $opt in
    l)  LastEmergeOperation
        ;;
    o)  Overall
        ;;
    p)  PackagesPerDay
        ;;
    t)  CurrentTask
        ;;
    *)  echo "call: $(basename $0) [-l] [-o] [-p] [-t]"
        echo
        exit 0
        ;;
  esac
done

echo
