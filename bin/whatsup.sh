#!/bin/sh
#
#set -x

# quick & dirty stats
#

# all active|running images
#
function list_images() {
  (
    cd ~
    ls -1d run/* | xargs -n 1 readlink | cut -f2- -d'/'
    df -h | grep '/tinderbox/img./' | cut -f4-5 -d'/'
  ) | sort -u
}


# gives sth. like:
#
# emerged failed  days    backlog rate    ~/run   locked
# 7927    115     35.9    13409   155             yes     gnome-systemd-unstable_20161228-112305
# 6110    108     10.5    12991   572     yes             13.0-no-multilib-libressl-unstable_20170122-225602
# 3029    45      3.0     16921   693     yes             13.0-systemd-libressl-unstable_20170130-102323
# 6185    90      10.1    14245   470     yes     yes     13.0-unstable_20170123-090431
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
# gnome-unstable_20170201-093005                    655   56
# hardened-no-multilib-libressl-unstable_20170131- 1062  798
# hardened-unstable_20170129-183636                 344  870 1045  503
#
function PackagesPerDay() {
  for i in $images
  do
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    qlop -lC -f $i/var/log/emerge.log |\
    perl -wane '
      BEGIN { %h   = (); $i = 0; $old = 0; }
      {
        my $day = $F[2];
        my ($hh, $mm, $ss) = split (/:/, $F[3]);

        $cur = $day * 24*60*60 + $hh * 60*60 + $mm * 60 + $ss;

        # month changed ?
        #
        if ($cur < $old)  {
          $old = $old % 86400;
        }

        if ($cur - $old > 86400) {
          $old = $cur;
          $i++;
        }
        $h{$i}++;
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
# gnome-stable_20170122-104332                       0: 0:19 hrs  dev-php/PEAR-File
# gnome-systemd-libressl-unstable_20170202-095758    1: 5:12 hrs  %emerge -u sys-devel/gcc
# gnome-unstable_20170201-093005                     0: 0:33 hrs  media-gfx/zbar
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
