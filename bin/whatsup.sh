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


function PrintImageName()  {
  printf "%s\r\t\t\t\t\t               \r\t\t\t\t\t" $(basename $i)
}


# gives sth. like:
#
#  4243   64   5.1  15304     y    y      13.0-systemd-libressl-unstable-abi32+64_20170210-142202
#    14    0   0.0  18970          y      desktop-libressl-abi32+64_20170215-185650
#  6316   71   9.0   9631     y    y    y desktop-stable_20170206-184215
#
function Overall() {
  echo " inst fail   day   todo ~/run lock stop"
  for i in $images
  do
    log=$i/var/log/emerge.log
    if [[ -f $log ]]; then
      inst=$(grep -c '::: completed emerge' $log)
      day=$(echo "scale=1; ($(tail -n1 $log | cut -c1-10) - $(head -n1 $log | cut -c1-10)) / 86400" | bc)
    else
      inst=0
      day=0
    fi
    # count fail packages, but not every failed attempt of the same package version
    #
    if [[ -d $i/tmp/issues ]]; then
      fail=$(ls -1 $i/tmp/issues | xargs -n 1 basename | cut -f2- -d'_' | sort -u | wc -w)
    else
      fail=0
    fi
    todo=$(wc -l < $i/tmp/packages 2>/dev/null)

    [[ -e ~/run/$(basename $i) ]] && run="y"  || run=""
    [[ -f $i/tmp/LOCK ]]          && lock="y" || lock=""
    [[ -f $i/tmp/STOP ]]          && stop="y" || stop=""

    printf "%5i %4i  %4.1f  %5i %5s %4s %4s %s\n" $inst $fail $day $todo "$run" "$lock" "$stop" $(basename $i)
  done
}


# gives sth. like:
#
# 13.0-no-multilib-unstable_20170203-15343   0h  0m 24s *** app-crypt/manuale
# 13.0-systemd-libressl-unstable-abi32+64_   0h  3m 45s >>> (4 of 9) net-nds/openldap-2.4.44-r1
# desktop-stable_20170206-184215             0h  0m 20s ::: (2 of 2) media-video/vamps-0.99.2
#
function LastEmergeOperation()  {
  for i in $images
  do
    PrintImageName
    log=$i/var/log/emerge.log
    if [[ ! -f $log ]]; then
      echo
      continue
    fi

    tac $log |\
    grep -m 1 -E -e '(>>>|\*\*\*) emerge' -e ' \*\*\* terminating.' -e '::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* terminating\./ /g' |\
    perl -wane '
      chop ($F[0]);

      my $diff = time() - $F[0];
      my $hh = $diff / 60 / 60;
      my $mm = $diff / 60 % 60;
      my $ss = $diff % 60 % 60;

      printf (" %2ih %2im %02is %s\n", $hh, $mm, $ss, join (" ", @F[1..$#F]));
    '
  done
}


# gives sth. like:
#
# gnome-systemd-unstable_20170203-145554     5431019 946 803 511 564 771 596 598 237
# gnome-unstable_20170201-093005             655 940 984 568 639 500 301 407 320 596 494 430  18
# plasma-stable_20170206-185342              589 729 950 8021011 768 344
#
function PackagesPerDay() {
  for i in $images
  do
    PrintImageName
    log=$i/var/log/emerge.log
    if [[ ! -f $log ]]; then
      echo
      continue
    fi

    # qlop gives sth like: Fri Aug 19 13:43:15 2016 >>> app-portage/cpuid2cpuflags-1
    #
    grep '::: completed emerge' $log |\
    cut -f1 -d ':' |\
    perl -wane '
      BEGIN { @p = (); $first = 0; }
      {
        $cur = $F[0];
        $first = $cur if ($first == 0);
        my $i = int (($cur-$first)/86400);
        $p[$i]++;
      }

      END {
        foreach my $i (0..$#p) {
          printf ("%5i", $p[$i]);
        }
        print "\n";
      }
    '
  done
}


# gives sth. like:
#
# 13.0-no-multilib-unstable_20170203-15343   0h  1m 01s  app-benchmarks/volanomark
# 13.0-systemd-libressl-unstable-abi32+64_   0h  9m 14s  sci-astronomy/cpl
# desktop-stable_20170206-184215             1h 35m 56s  dev-lang/mercury
#
function CurrentTask()  {
  for i in $images
  do
    PrintImageName
    tsk=$i/tmp/task
    if [[ ! -f $tsk ]]; then
      echo
      continue
    fi

    delta=$(echo "$(date +%s) - $(date +%s -r $tsk)" | bc)
    seconds=$(echo "$delta % 60" | bc)
    minutes=$(echo "$delta / 60 % 60" | bc)
    hours=$(echo "$delta / 60 / 60" | bc)
    printf " %2ih %2im %02is  " $hours $minutes $seconds
    cat $i/tmp/task
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
