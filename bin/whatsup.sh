#!/bin/sh
#
# set -x

# quick & dirty stats
#

# all active|running images
#
function list_images() {
  (
    ls -1d ~/run/* | xargs -n 1 readlink | sed "s,^..,/home/tinderbox,g"
    df -h | grep '/home/tinderbox/img./' | cut -f4-5 -d'/' | sed "s,^,/home/tinderbox/,g"
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
    if [[ -f $log ]]; then
      emerged=$(qlop -lC -f $log | wc -l)
      if [[ -d $i/tmp/issues ]]; then
        failed=$(ls -1 $i/tmp/issues | xargs -n 1 basename | cut -f2- -d'_' | sort -u | wc -w)
      else
        failed="-"
      fi
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
      if [[ -f $i/tmp/LOCK ]]; then
        lock="yes"
      else
        lock=""
      fi

      echo -e "$emerged\t$failed\t$days\t$backlog\t$rate\t$run\t$lock\t$(basename $i)"
    else
      echo -e "\t\t\t\t\t\t\t$(basename $i)"
    fi
  done
}


# gives sth. like:
#
# 13.0-no-multilib-unstable_20170203-153432          0h  0m 37s >>> (1 of 1) dev-php/pecl-timezonedb-2016.10
# desktop-stable_20170206-184215                     1h  0m 46s >>> (23 of 25) dev-games/openscenegraph-3.4.0
# desktop-unstable_20170127-120123                   0h  0m 58s
#
function LastEmergeOperation()  {
  for i in $images
  do
    log=$i/var/log/emerge.log
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    if [[ -f $log ]]; then
      tac $log |\
      grep -m 1 -E '(>>>|\*\*\*|===) emerge' |\
      sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ \*\*\*.*//g' |\
      perl -wane '
        chop ($F[0]);

        my $diff = time() - $F[0];
        my $hh = $diff / 60 / 60;
        my $mm = $diff % 60 / 60;
        my $ss = $diff % 60 % 60;

        printf ("  %2ih %2im %02is %s\n", $hh, $mm, $ss, join (" ", @F[1..$#F]));
      '
    else
      ls -l $log
      echo
    fi
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
    log=$i/var/log/emerge.log
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    if [[ -f $log ]]; then
      qlop -lC -f $log |\
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
            printf ("  %5i", $h{$k});
          }
        }
      '
      echo " "
    else
      echo
    fi
  done
}


# gives sth. like:
#
# 13.0-no-multilib-unstable_20170203-153432          0h  0m 52s  games-puzzle/tanglet
# 13.0-systemd-libressl-unstable_20170130-102323     0h  0m 39s  @preserved-rebuild
# desktop-unstable_20170127-120123                   0h  2m 00s  app-text/bibletime
#
function CurrentTask()  {
  for i in $images
  do
    tsk=$i/tmp/task
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    if [[ -f $tsk ]]; then
      delta=$(echo "$(date +%s) - $(date +%s -r $tsk)" | bc)
      seconds=$(echo "$delta % 60" | bc)
      minutes=$(echo "$delta / 60 % 60" | bc)
      hours=$(echo "$delta / 60 / 60" | bc)
      printf "  %2ih %2im %02is  " $hours $minutes $seconds
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
#   exec 3>&2
#   exec 2> /dev/null

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

#   exec 2>&3
done

echo
