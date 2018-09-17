#!/bin/sh
#
# set -x

# few tinderbox statistics
#

# watch all images either symlinked into ~/run or running
#
function list_images() {
  (
    for i in $(ls ~/run); do echo ~/img?/$i; done
    df -h | grep '/home/tinderbox/img./' | cut -f4-5 -d'/' -s | sed "s,^,/home/tinderbox/,g"
  ) | sort -u -k 5 -t'/'
}

# ${n} should be the minimum length to distinguish abbreviated image names
#
function PrintImageName()  {
  n=34

  string="$(basename $i | cut -c1-$n)"
  printf "%-${n}s" $string
}


function check_history()  {
  local file=$1
  local lc=$2

  if [[ -s $file ]]; then
    tail -n 1 $file | grep -q "20.. ok[ ]*$"
    if [[ $? -eq 0 ]]; then
      flag=" $flag"
      return
    fi

    tail -n 1 $file | grep -q "20.. NOT ok"
    if [[ $? -eq 0 ]]; then
      local uc=$(echo $lc | tr '[:lower:]' '[:upper:]')
      flag="${uc}${flag}"
      return
    fi

    flag="${lc}${flag}"
    return
  fi

  flag=".$flag"
  return
}

# gives sth. like:
#
# compl fail  days backlog  upd  1st status
#  3735   41   3.6   16369    0    1   W  r  run/13.0-no-multilib_20170315-195201
#  6956   75   9.6   13285    0    0     fr  run/13.0-systemd_20170309-190652
#  10      0   0.0   19301    2    8        img2/13.0-systemd-libressl_20170316-210316
#
function Overall() {
  running=0
  for i in $images
  do
    if [[ -f $i/tmp/LOCK ]]; then
      let "running = running + 1"
    fi
  done
  inrun=$(echo $images | wc -w)
  overall=$(ls -1d ~/img?/* | wc -w)

  echo "compl fail  days backlog  upd  1st status  $running#$inrun images running ($overall at all)"

  for i in $images
  do
    compl=0
    fail=0
    day=0

    log=$i/var/log/emerge.log
    if [[ -f $log ]]; then
      compl=$(grep -c '::: completed emerge' $log)
      t1=$(head -n 1 $log | cut -c1-10)
      t2=$(date +%s)
      day=$(echo "scale=1; ($t2 - $t1) / 86400" | bc)
    fi

    # count emerge failures based on distinct package release
    # example of an issue directory name: 20170417-082345_app-misc_fsniper-1.3.1-r2
    #
    if [[ -d $i/tmp/issues ]]; then
      fail=$(ls -1 $i/tmp/issues | xargs -n 1 basename 2>/dev/null | cut -f2- -d'_' -s | sort -u | wc -w)
    fi

    bl=$(wc -l 2>/dev/null < $i/tmp/backlog)
    bl1=$(wc -l 2>/dev/null < $i/tmp/backlog.1st)
    blu=$(wc -l 2>/dev/null < $i/tmp/backlog.upd)
    ((bl=bl+0))
    ((bl1=bl1+0))
    ((blu=blu+0))

    flag=""
    [[ -f $i/tmp/LOCK ]] && flag="r$flag" || flag=" $flag"    # (r)unning
    [[ -f $i/tmp/STOP ]] && flag="f$flag" || flag=" $flag"    # (f)inishing

    flag=" $flag"

    # show result of last run of @system, @world and @preserved-rebuild respectively
    # upper case: an error occurred, lower case: a warning occurred
    # a "." means was not run yet and a space, that it was fully ok
    #
    check_history $i/tmp/@world.history              w
    check_history $i/tmp/@system.history             s
    check_history $i/tmp/@preserved-rebuild.history  p

    b=$(basename $i)
    [[ -e ~/run/$b ]] && d="run" || d=$(basename $(dirname $i))

    printf "%5i %4i %5.1f %7i %4i %4i %6s %4s/%s\n" $compl $fail $day $bl $blu $bl1 "$flag" "$d" "$b"
  done
}


# gives sth. like:
#
# 13.0-abi32+64_20170216-202818              1:53 m  mail-filter/assp
# desktop_20170218-203252                    1:11 h  games-emulation/sdlmame
# desktop-libressl-abi32+64_20170215-18565   0:03 m  dev-ruby/stringex
#
function CurrentTask()  {
  ts=$(date +%s)
  for i in $images
  do
    PrintImageName
    if [[ ! -f $i/tmp/LOCK ]]; then
      echo
      continue
    fi

    tsk=$i/tmp/task
    if [[ ! -s $tsk ]]; then
      echo
      continue
    fi

    task=$(cat $tsk 2>/dev/null)
    if [[ -z "$task" ]]; then
      echo
      continue
    fi

    let "delta = $ts - $(stat -c%Y $tsk 2>/dev/null)" 2>/dev/null

    if [[ $delta -ge 3600 ]]; then
      let "minutes = $delta / 60 % 60"
      let "hours = $delta / 60 / 60"
      printf " %3i:%02i h  " $hours $minutes
    else
      let "minutes = $delta / 60 % 60"
      let "seconds = $delta % 60 % 60"
      printf " %3i:%02i m  " $minutes $seconds
    fi
    echo $task
  done
}


# gives sth. like:
#
# 13.0-abi32+64_20170216-202818              0:13 m  >>> (5 of 8) dev-perl/Email-MessageID-1.406.0
# desktop_20170218-203252                    1:10 h  >>> (1 of 1) games-emulation/sdlmame-0.174
# desktop-libressl-abi32+64_20170215-18565   0:32 m  *** dev-ruby/stringex
#
function LastEmergeOperation()  {
  for i in $images
  do
    PrintImageName
    if [[ ! -f $i/tmp/LOCK ]]; then
      echo
      continue
    fi

    if [[ ! -s $i/var/log/emerge.log ]]; then
      echo
      continue
    fi

    # catch the last *started* emerge operation
    #
    tac $i/var/log/emerge.log 2>/dev/null |\
    grep -m 1 -E -e '>>>|\*\*\* emerge' -e ' \*\*\* terminating.' -e '::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* .*/ /g' |\
    perl -wane '
      chop ($F[0]);

      my $delta = time() - $F[0];
      if ($delta >= 3600) {
        $minutes = $delta / 60 % 60;
        $hours = $delta / 60 / 60;
        printf (" %3i:%02i h ", $hours, $minutes);
      } else  {
        $minutes = $delta / 60 % 60;
        $seconds = $delta % 60 % 60;
        printf (" %3i:%02i m ", $minutes, $seconds);
      }
      printf (" %s\n", join (" ", @F[1..$#F]));
    '
  done
}


# gives sth. like:
#
# gnome-systemd_20170301-222559     793 1092  696  315
# plasma-abi32+64_20170216-195507   454 1002  839  672 1111  864 691. 719 665 469 521 487 460 403  453 388 248
# plasma-abi32+64_20170228-094845   627  462 1111  718  546  182
#
function PackagesPerDay() {
  for i in $images
  do
    PrintImageName

    if [[ ! -s $i/var/log/emerge.log ]]; then
      echo
      continue
    fi

    grep '::: completed emerge' $i/var/log/emerge.log 2>/dev/null |\
    cut -f1 -d ':' -s |\
    perl -wane '
      BEGIN { @p = (0); $first = 0; }
      {
        $cur = $F[0];
        $first = $cur if ($first == 0);
        my $i = int (($cur-$first)/86400);
        $p[$i]++;
      }

      END {
        foreach my $i (0..$#p) {
          $p[$i] = 0 unless ($p[$i]);

          # the first $d days usually have >1,000 completed emerge operations
          #
          $d = 4;
          if ($i < $d)  {
            printf "%5i", $p[$i]
          } else  {
            printf "%4i", $p[$i]
          }

          # mark a 7-day period
          #
          if ($i != $#p && $i % 7 == 6)  {
            print ".";
          }
        }
        print "\n";
      }
    '
  done
}


#######################################################################
#
images=$(list_images)

while getopts hlopt\? opt
do
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
  echo
done
