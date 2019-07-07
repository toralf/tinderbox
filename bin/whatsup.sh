#!/bin/bash
#
# set -x

# print tinderbox statistics


# watch all images either runnign or at least symlinked into ~/run
#
function list_images() {
  {
    for i in $( ls ~/run ); do ls -d ~/img?/$i; done
    df -h | grep '/home/tinderbox/img./' | cut -f4-5 -d'/' -s | sed "s,^,/home/tinderbox/,g"
  } 2>/dev/null | sort -u
}


# ${n} should be the minimum length to clearly distinguish the images
#
function PrintImageName()  {
  n=32

  printf "%-${n}s " $(cut -c-$n <<< ${i##*/})
}


function check_history()  {
  local file=$1
  local lc=$2

  if [[ -s $file ]]; then
    tail -n 1 $file | grep -q " NOT ok "
    if [[ $? -eq 0 ]]; then
      local uc=$(echo $lc | tr '[:lower:]' '[:upper:]')
      flag="${uc}${flag}"
      return
    fi

    tail -n 1 $file | grep -q " ok "
    if [[ $? -eq 0 ]]; then
      flag=" $flag"
      return
    fi

    flag="${lc}${flag}"
    return
  fi

  flag=".$flag"
  return
}


# whatsup.sh -o
#
# compl fail  days backlog  upd  1st state
#  3735   41   3.6   16369    0    1 pS  r  run/13.0-no-multilib_20170315-195201
#  6956   75   9.6   13285    0    0    fr  run/13.0-systemd_20170309-190652
#  10      0   0.0   19301    2    8 ...   img2/13.0-systemd-libressl_20170316-210316
#
function Overall() {
  running=0
  for i in $images
  do
    if [[ -f $i/tmp/LOCK ]]; then
      let "running = running + 1"
    fi
  done
  inrun=$(wc -w <<< $images)

  echo "compl fail  days backlog  upd  1st state  $running#$inrun images are up"

  for i in $images
  do
    day=0
    f=$i/tmp/setup.sh
    if [[ -f $f ]]; then
      let "age = $(date +%s) - $(stat -c%Y $f)"
      day=$( echo "scale=2; $age / 86400.0" | bc )
    fi

    compl=0
    f=$i/var/log/emerge.log
    if [[ -f $f ]]; then
      compl=$(grep -c ' ::: completed emerge' $f)
    fi

    # count emerge failures based on distinct package release
    # example of an issue directory name: 20170417-082345_app-misc_fsniper-1.3.1-r2
    #
    fail=0
    if [[ -d $i/tmp/issues ]]; then
      fail=$(ls -1 $i/tmp/issues | xargs --no-run-if-empty -n 1 basename | cut -f2- -d'_' -s | sort -u | wc -w)
    fi

    bl=$(wc -l 2>/dev/null < $i/tmp/backlog)
    bl1=$(wc -l 2>/dev/null < $i/tmp/backlog.1st)
    blu=$(wc -l 2>/dev/null < $i/tmp/backlog.upd)

    flag=""
    [[ -f $i/tmp/LOCK ]] && flag="r$flag" || flag=" $flag"    # (r)unning

    # (f)inishing
    if [[ -f $i/tmp/STOP ]]; then
      flag="F$flag"
    else
      grep -q ^STOP $i/tmp/backlog.1st
      if [[ $? -eq 0 ]]; then
        flag="f$flag"
      else
        flag=" $flag"
      fi
    fi

    # just an additional space
    #
    flag="$flag"

    # show result of last run of @system, @world and @preserved-rebuild respectively
    # upper case: an error occurred, lower case: a warning occurred
    # a "." means was not run yet and a space, that it was fully ok
    #
    check_history $i/tmp/@world.history              w
    check_history $i/tmp/@system.history             s
    check_history $i/tmp/@preserved-rebuild.history  p

    # images during setup are not already symlinked to ~/run, print so that the position of / is fixed
    #
    b=${i##*/}
    [[ -e ~/run/$b ]] && d="run" || d=$(basename $(dirname $i))

    printf "%5i %4i %5.1f %7i %4i %4i %5s %4s/%s\n" $compl $fail $day $bl $blu $bl1 "$flag" "$d" "$b"
  done
}


# whatsup.sh -t
#
# 13.0-abi32+64_20170216-202818              1:53 m  mail-filter/assp
# desktop_20170218-203252                    1:11 h  games-emulation/sdlmame
# desktop-libressl-abi32+64_20170215-18565   0:03 m  dev-ruby/stringex
#
function Tasks()  {
  ts=$(date +%s)
  for i in $images
  do
    PrintImageName

    tsk=$i/tmp/task
    if [[ ! -f $i/tmp/LOCK || ! -s $tsk ]]; then
      echo
      continue
    fi

    let "delta = $ts - $(stat -c%Y $tsk)" 2>/dev/null

    if [[ $delta -lt 3600 ]]; then
      let "minutes = $delta / 60 % 60"
      let "seconds = $delta % 60 % 60"
      printf "%3i:%02i m " $minutes $seconds
    else
      let "hours = $delta / 60 / 60"
      let "minutes = $delta / 60 % 60"
      printf "%3i:%02i h " $hours $minutes
    fi

    task=$(cat $tsk)
    if [[ ! $task =~ "@" && ! $task =~ "%" ]]; then
      echo -n " "
    fi
    echo $task
  done
}


# whatsup.sh -l
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
    grep -m 1 -E -e ' >>>| \*\*\* emerge' -e ' \*\*\* terminating.' -e ' ::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* .*/ /g' |\
    perl -wane '
      chop ($F[0]);
      my $delta = time() - $F[0];
      if ($delta < 3600) {
        $minutes = $delta / 60 % 60;
        $seconds = $delta % 60 % 60;
        printf ("%3i:%02i m", $minutes, $seconds);
      } else  {
        $hours = $delta / 60 / 60;
        $minutes = $delta / 60 % 60;
        printf ("%3i:%02i h", $hours, $minutes);
      }
      print join (" ", " ", @F[1..$#F]), "\n";
    '
  done
}


# whatsup.sh -p
#
# gnome-systemd_20170301-222559     793 1092  696  315
# plasma-abi32+64_20170216-195507   454 1002  839  672 1111  864 691. 719 665 469 521 487 460 403. 453
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

    perl -F: -wane '
      # @p helds the amount of emerge operations of day $i
      BEGIN {
        @p = (0);
        $first = 0;
      }
      {
        next unless (m/::: completed emerge/);
        $curr = $F[0];
        $first = $curr unless ($first);
        my $i = ($curr-$first) / 86400;
        $p[$i]++;
      }

      END {
        foreach my $i (0..$#p) {
          $p[$i] = 0 unless ($p[$i]);               # set missing value to zero
          printf "%5i", $p[$i];
          print "." if ($i != $#p && $i % 7 == 6);  # mark a week
        }
        print "\n";
      }
    ' $i/var/log/emerge.log
  done
}


#######################################################################
#
unset LC_TIME
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
    t)  Tasks
        ;;
    *)  echo "call: ${0##*/} [-l] [-o] [-p] [-t]"
        echo
        exit 0
        ;;
  esac
  echo
done
