#!/bin/bash
# set -x

# print tinderbox statistics


function list_images() {
  (
    ls ~tinderbox/run/
    ls /run/tinderbox/ | sed 's,.lock,,g'
  ) |\
  sort -u |\
  while read i
  do
    ls -d ~tinderbox/img{1,2}/${i} 2>/dev/null
  done |\
  sort -k 5 -t'/'
}


function __is_running() {
  [[ -d "/run/tinderbox/${1##*/}.lock" ]]
}


function PrintImageName()  {
  # ${n} should be the minimum length to distinguish image names
  n=22
  printf "%-${n}s" $(cut -c-$n <<< ${1##*/})
}


function check_history()  {
  file=$1
  lc=$2

  # eg. for @system:
  # X = @x failed at all to start
  # x = @x failed due to a package issue
  # . = never run before
  #   = no issues
  if [[ -s $file ]]; then
    if tail -n 1 $file | grep -q " NOT ok"; then
      uc=$(echo $lc | tr '[:lower:]' '[:upper:]')
      flag="${uc}${flag}"
      return
    fi

    if tail -n 1 $file | grep -q " ok"; then
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
# compl fail days backlog  upd  1st status  8#8 locked
#   764   31  1.8   18847  153    0    l K  run/17.0_musl-20200311-204810
#  3415   92  3.1   15925  114    0    ls   run/17.1-libressl-20200310-153510
#   271   13  3.4   19037  546   18 ..wlS   run/17.1_desktop-test-20200310-081612
#  2934   74  4.8   17974  535    0         run/17.1_desktop_plasma-libressl-20200308-224459
function Overall() {
  running=$(ls -d /run/tinderbox/*.lock 2>/dev/null | wc -l)
  all=$(wc -w <<< $images)
  echo "compl fail days backlog .upd .1st status  $running#$all running"

  for i in $images
  do
    day=0
    f=$i/var/tmp/tb/setup.sh
    if [[ -f $f ]]; then
      let "age = $(date +%s) - $(stat -c%Y $f)" || true
      day=$(echo "scale=1; $age / 86400.0" | bc)
    fi

    compl=0
    f=$i/var/log/emerge.log
    if [[ -f $f ]]; then
      compl=$(grep -c ' ::: completed emerge' $f) || true
    fi

    # count emerge failures based on distinct package name+version+release
    # example of an issue directory name: 20200313-044024-net-analyzer_iptraf-ng-1.1.4-r3
    fail=0
    if [[ -d $i/var/tmp/tb/issues ]]; then
      fail=$(ls -1 $i/var/tmp/tb/issues | while read i; do echo ${i##/*}; done | cut -f3- -d'-' -s | sort -u | wc -w)
    fi

    bl=$(wc -l  2>/dev/null < $i/var/tmp/tb/backlog)
    bl1=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.1st)
    blu=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.upd)

    flag=""
    if __is_running $i ; then
      flag="${flag}r"
    else
      flag="$flag "
    fi

    # F=STOP file, f=STOP in backlog
    if [[ -f $i/var/tmp/tb/STOP ]]; then
      flag="${flag}S"
    else
      if grep -q "^STOP" $i/var/tmp/tb/backlog.1st; then
        flag="${flag}s"
      else
        flag="$flag "
      fi
    fi

    [[ -f $i/var/tmp/tb/KEEP ]] && flag="${flag}K" || flag="$flag "

    # show result of last run of @system, @world and @preserved-rebuild respectively
    # upper case: an error occurred, lower case: a warning occurred
    # a "." means was not run yet and a space, that it was fully ok
    check_history $i/var/tmp/tb/@world.history              w
    check_history $i/var/tmp/tb/@system.history             s
    check_history $i/var/tmp/tb/@preserved-rebuild.history  p

    # images during setup are not already symlinked to ~/run, print so that the position of / is fixed
    b=${i##*/}
    if [[ -e ~/run/$b ]]; then
      d="run"
    else
      d=${i%/*}
      d=${d##*/}
    fi

    printf "%5i %4i %4.1f %7i %4i %4i %6s %4s/%s\n" $compl $fail $day $bl $blu $bl1 "$flag" "$d" "$b" 2>/dev/null
  done
}


# whatsup.sh -t
# 13.0-abi32+64_20170216-202818              1:53 m  mail-filter/assp
# desktop_20170218-203252                    1:11 h  games-emulation/sdlmame
# desktop-libressl-abi32+64_20170215-18565   0:03 m  dev-ruby/stringex
function Tasks()  {
  ts=$(date +%s)
  for i in $images
  do
    PrintImageName $i
    if ! __is_running $i ; then
      echo
      continue
    fi

    tsk=$i/var/tmp/tb/task
    if [[ ! -s $tsk ]]; then
      echo
      continue
    fi
    task=$(cat $tsk)

    let "delta = $ts - $(stat -c%Y $tsk)" || true

    if [[ $delta -lt 3600 ]]; then
      let "minutes = $delta / 60 % 60"  || true
      let "seconds = $delta % 60 % 60"  || true
      printf "%3i:%02i m " $minutes $seconds
    else
      let "hours = $delta / 60 / 60"    || true
      let "minutes = $delta / 60 % 60"  || true
      printf "%3i:%02i h " $hours $minutes
    fi

    if [[ ! $task =~ "@" && ! $task =~ "%" && ! $task =~ "#" ]]; then
      echo -n " "
    fi
    echo $task
  done
}


# whatsup.sh -l
# 13.0-abi32+64_20170216-202818              0:13 m  >>> (5 of 8) dev-perl/Email-MessageID-1.406.0
# desktop_20170218-203252                    1:10 h  >>> (1 of 1) games-emulation/sdlmame-0.174
# desktop-libressl-abi32+64_20170215-18565   0:32 m  *** dev-ruby/stringex
function LastEmergeOperation()  {
  for i in $images
  do
    PrintImageName $i
    if ! __is_running $i ; then
      echo
      continue
    fi

    # catch the last *started* emerge operation
    tac $i/var/log/emerge.log 2>/dev/null |\
    grep -m 1 -E -e ' >>>| \*\*\* emerge' -e ' \*\*\* terminating.' -e ' ::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* .*/ /g' |\
    perl -wane '
      next if (scalar @F < 2);

      chop ($F[0]);
      my $delta = time() - $F[0];

      if ($delta < 3600) {
        $minutes = $delta / 60 % 60;
        $seconds = $delta % 60 % 60;
        printf ("%3i:%02i m  ", $minutes, $seconds);
      } else  {
        $hours = $delta / 60 / 60;
        $minutes = $delta / 60 % 60;
        # note long runtimes
        printf ("%3i:%02i h%s ", $hours, $minutes, $hours < 8 ? " " : "!");
      }
      print join (" ", @F[1..$#F]);
    '
    echo
  done
}


# whatsup.sh -p
# gnome-systemd_20170301-222559     793 1092  696  315
# plasma-abi32+64_20170216-195507   454 1002  839  672 1111  864 691. 719 665 469 521 487 460 403. 453
# plasma-abi32+64_20170228-094845   627  462 1111  718  546  182
function PackagesPerDay() {
  for i in $images
  do
    PrintImageName $i

    perl -F: -wane '
      # @p helds the amount of emerge operations of day $i
      BEGIN {
        @p = (0);
        $first = 0;
      }

      # calculate these values for the case that current emerge runs longer than 1 day
      my $curr = $F[0];
      $first = $curr unless ($first);
      my $i = ($curr - $first) / 86400;

      next unless (m/::: completed emerge/);
      $p[$i]++;

      END {
        $p[$i] += 0;    # set end date nevertheless whether the emerge operations finished or not
        foreach my $i (0..$#p) {
          if ($i < 8 || $i % 7 == 0) {
            (exists $p[$i]) ? printf "%5i", $p[$i] : printf "    -";
          } else {
            (exists $p[$i]) ? printf "%4i", $p[$i] : printf "   -";
          }
        }
        print "\n";
      }
    ' $i/var/log/emerge.log 2>/dev/null
  done
}


# whatsup.sh -c
# 1x: 4800   2x: 2199   3x: 1037   4x: 765   5x: 562   6x: 525   7x: 537   8x: 125
function CountPackages()  {
  for i in $images
  do
    grep -F ' ::: completed emerge' $i/var/log/emerge.log 2>/dev/null | cut -f9 -d' ' -s
  done |\
  perl -wne '
    BEGIN {
      my %emergesPerPackage = ();     # how often a particular package was emerged
      my $total = 0;                  # total amount of emerge operations
    }

    chomp();
    $emergesPerPackage{$_}++;

    END {
      my %h = ();

      # count the "amount of emerge" values
      for my $key (keys %emergesPerPackage)  {
        my $value = $emergesPerPackage{$key};
        $h{$value}++;
        $total += $value;
        print $value, "x ", $key, "\n" if ($value > 21);
      }

      my $unique = 0; # packages
      for my $key (sort { $a <=> $b } keys %h)  {
        my $value = $h{$key};
        printf "%i%s%i  ", $key, "x", $value;   # "amount of packages" "x" "which were emerged N times"
        $unique += $value;
      }

      print "\ntotal = $total  unique = $unique\n";
    }
  '
}


#######################################################################
set -eu
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
