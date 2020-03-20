#!/bin/bash
#
# set -x

# print tinderbox statistics


# watch any images either mounted or symlinked into ~/run
#
function list_images() {
  {
    for i in $(ls ~/run)
    do
      ls -d ~/img?/$i
    done
    df -h | grep '/home/tinderbox/img./' | cut -f1-5 -d'/' -s | awk ' { print $6 } '
  } 2>/dev/null | sort -u -k 5 -t'/'
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

  # eg. for @system:
  #
  # S = failed at all
  # s = failed for a package
  # . = never run before
  #   = no issues
  #
  if [[ -s $file ]]; then
    tail -n 1 $file | grep -q " NOT ok"
    if [[ $? -eq 0 ]]; then
      local uc=$(echo $lc | tr '[:lower:]' '[:upper:]')
      flag="${uc}${flag}"
      return
    fi

    tail -n 1 $file | grep -q " ok"
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
# compl fail days backlog  upd  1st status  8#8 running
#   764   31  1.8   18847  153    0    r K  run/17.0_musl-20200311-204810
#  3415   92  3.1   15925  114    0    r    run/17.1-libressl-20200310-153510
#   271   13  3.4   19037  546   18 ..wrSK  run/17.1_desktop-test-20200310-081612
#  2934   74  4.8   17974  535    0    r    run/17.1_desktop_plasma-libressl-20200308-224459
function Overall() {
  running=0
  for i in $images
  do
    if [[ -f $i/var/tmp/tb/LOCK ]]; then
      let "running = running + 1"
    fi
  done
  inrun=$(wc -w <<< $images)

  echo "compl fail days backlog  upd  1st status  $running#$inrun running"

  for i in $images
  do
    day=0
    f=$i/var/tmp/tb/setup.sh
    if [[ -f $f ]]; then
      let "age = $(date +%s) - $(stat -c%Y $f)"
      day=$( echo "scale=1; $age / 86400.0" | bc )
    fi

    compl=0
    f=$i/var/log/emerge.log
    if [[ -f $f ]]; then
      compl=$(grep -c ' ::: completed emerge' $f)
    fi

    # count emerge failures based on distinct package name+version+release
    # example of an issue directory name: 20200313-044024-net-analyzer_iptraf-ng-1.1.4-r3
    #
    fail=0
    if [[ -d $i/var/tmp/tb/issues ]]; then
      fail=$(ls -1 $i/var/tmp/tb/issues | xargs --no-run-if-empty -n 1 basename | cut -f3- -d'-' -s | sort -u | wc -w)
    fi

    bl=$(wc -l  2>/dev/null < $i/var/tmp/tb/backlog)
    bl1=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.1st)
    blu=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.upd)

    flag=""

    [[ -f $i/var/tmp/tb/LOCK ]] && flag="${flag}r" || flag="$flag "    # (r)unning or not?

    # F=STOP file, f=STOP in backlog
    if [[ -f $i/var/tmp/tb/STOP ]]; then
      flag="${flag}S"
    else
      grep -q ^STOP $i/var/tmp/tb/backlog.1st && flag="${flag}s" || flag="$flag "
    fi

    [[ -f $i/var/tmp/tb/KEEP ]] && flag="${flag}K" || flag="$flag "

    # show result of last run of @system, @world and @preserved-rebuild respectively
    # upper case: an error occurred, lower case: a warning occurred
    # a "." means was not run yet and a space, that it was fully ok
    #
    check_history $i/var/tmp/tb/@world.history              w
    check_history $i/var/tmp/tb/@system.history             s
    check_history $i/var/tmp/tb/@preserved-rebuild.history  p

    # images during setup are not already symlinked to ~/run, print so that the position of / is fixed
    #
    b=${i##*/}
    [[ -e ~/run/$b ]] && d="run" || d=$(basename ${i%/*})

    printf "%5i %4i %4.1f %7i %4i %4i %6s %4s/%s\n" $compl $fail $day $bl $blu $bl1 "$flag" "$d" "$b" 2>/dev/null
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

    tsk=$i/var/tmp/tb/task
    if [[ ! -f $i/var/tmp/tb/LOCK || ! -s $tsk ]]; then
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
    if [[ ! -f $i/var/tmp/tb/LOCK ]]; then
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
      print join (" ", " ", @F[1..$#F]);
    '
    echo
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

    perl -F: -wane '
      # @p helds the amount of emerge operations of day $i
      BEGIN {
        @p = (0);
        $first = 0;
      }

      # calculate these values for the case that current emerge runs longer than 1 day
      my $curr = $F[0];
      $first = $curr unless ($first);
      my $i = ($curr-$first) / 86400;

      next unless (m/::: completed emerge/);
      $p[$i]++;

      END {
        $p[$i] += 0;    # set end date nevertheless whether the emerge operations finished or not
        foreach my $i (0..$#p) {
          (exists $p[$i]) ? printf "%5i", $p[$i] : printf "    -";
        }
        print "\n";
      }
    ' $i/var/log/emerge.log 2>/dev/null
  done
}


# whatsup.sh -c
#
# 1x: 4800   2x: 2199   3x: 1037   4x: 765   5x: 562   6x: 525   7x: 537   8x: 125
#
function CountPackages()  {
  for i in $images
  do
    grep ' ::: completed emerge' $i/var/log/emerge.log 2>/dev/null
  done |\
  perl -wane '
    BEGIN {
      my %EmergeOpsPerPackage = ();     # emerges per package
      my $emops = 0;                    # total amount of emerge operations
    }

    chomp();

    my $package = $F[7];
    $EmergeOpsPerPackage{$package}++;
    $emops++;

    END {
      my %h = ();

      # count the "amount of emerge" values
      for my $key (keys %EmergeOpsPerPackage)  {
        my $value = $EmergeOpsPerPackage{$key};
        $h{$value}++;
#         print $value, "\t", $key, "\n" if ($value > 10);
      }

      my $unique = 0; # packages
      for my $key (sort { $a <=> $b } keys %h)  {
        my $value = $h{$key};
        printf "%i%s%i  ", $value, "x", $key;
        $unique += $value;
      }

      print "\nunique = $unique    emerge operations = $emops\n";
    }
  '
}


#######################################################################
#
export LANG=C.utf8
unset LC_TIME
images=$(list_images)

while getopts chlopt\? opt
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
    c)  CountPackages
        ;;
    *)  echo "call: ${0##*/} [-c] [-l] [-o] [-p] [-t]"
        echo
        exit 0
        ;;
  esac
  echo
done
