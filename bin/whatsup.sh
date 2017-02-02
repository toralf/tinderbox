#!/bin/sh
#
#set -x

# quick & dirty stats
#

# all active | running images
#
function list_images() {
  (
    cd ~
    ls -1d run/* 2>/dev/null | xargs -n 1 readlink | cut -f2- -d'/'
    df -h | grep '/tinderbox/img./' | cut -f4-5 -d'/'
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
    failed=$(ls -1 $i/tmp/issues | xargs -n 1 basename | cut -f2- -d'_' | sort -u | wc -w)
    days=$(echo "scale=1; ($(tail -n1 $log | cut -c1-10) - $(head -n1 $log | cut -c1-10)) / 86400" | bc)
    backlog=$(wc -l < $i/tmp/packages)
    rate=$(echo "(19000 - $backlog) / $days" | bc)

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
# 13.0-systemd-libressl-unstable_20170130-102323    16:08:46 >>> (1 of 1) media-sound/splay-0.9.5.2-r2
# 13.0-unstable_20170123-090431                     16:08:56 >>> (1 of 1) net-proxy/shadowsocks-libev-2.6.2
# desktop-stable_20170121-152726                    16:08:43
# gnome-stable_20170122-104332                      16:07:47 >>> (2 of 2) x11-terms/valaterm-0.6

function LastEmergeOperation()  {
  for i in $images
  do
    printf "%s\r\t\t\t\t\t\t  " $(basename $i)
    tac ~/$i/var/log/emerge.log |\
    grep -m 1 -E '(>>>|\*\*\*|===) emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ \*\*\*.*//g' |\
    perl -wane '
      chop ($F[0]);
      my @t = split (/\s+/, scalar localtime ($F[0]));
      print join (" ", $t[3], @F[1..$#F]), "\n";
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
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    if [[ -f $i/tmp/task ]]; then
      delta=$(echo "$(date +%s) - $(date +%s -r $i/tmp/task)" | bc)
      seconds=$(echo "$delta % 60" | bc)
      minutes=$(echo "$delta / 60 % 60" | bc)
      hours=$(echo "$delta / 60 / 60" | bc)
      printf "  %2i:%2i:%02i hrs  " $hours $minutes $seconds
      cat $i/tmp/task
    else
      echo
    fi
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

  # ignore stderr but keep its setting
  #
  exec 3>&2
  exec 2> /dev/null

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

  exec 2>&3
done

echo
