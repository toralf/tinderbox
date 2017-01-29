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
# emerged days    backlog rate
# 5953    8.1     12905   752     13.0-libressl-unstable_20170110-100022
# 5259    7.1     14913   575     13.0-systemd-unstable_20170111-105830
# 5704    8.5     14096   576     13.0-unstable_20170109-235418
#
function Overall() {
  echo "emerged days    backlog rate"
  se=0; sre=0; srp=0

  for i in $images
  do
    log=$i/var/log/emerge.log
    e=$(qlop -lC -f $log | wc -l)
    d=$(echo "scale=1; ($(tail -n1 $log | cut -c1-10) - $(head -n1 $log | cut -c1-10)) / 86400" | bc)
    p=$(wc -l < $i/tmp/packages)
    rp=$(echo "(19000 - $p) / $d" | bc 2>/dev/null)
    if [[ $rp -le 0 || $rp -gt 3000 ]]; then
      rp='-'
    fi
    echo -e "$e\t$d\t$p\t$rp\t$(basename $i)"
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
  done |\
  sort
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


#######################################################################
#
images=$(list_images)

while getopts lop opt
do
  echo
  case $opt in
    l)  LastEmergeOperation
        ;;
    o)  Overall
        ;;
    p)  PackagesPerDay
        ;;
    *)  echo "call: $(basename $0) [-o] [-l] [-p]"
        exit 0
        ;;
  esac
  echo
done
