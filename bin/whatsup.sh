#!/bin/sh
#
#set -x

# quick & dirty stats
#

function Overall() {
  echo
  echo "emerged days    backlog rate"
  se=0; sre=0; srp=0
  ls -1d ~/run/* |\
  while read i
  do
    e=$(qlop -lC -f $i/var/log/emerge.log | wc -l)
    d=$(echo "scale=1; ($(tail -n1 $i/var/log/emerge.log | cut -c1-10)-$(head -n1 $i/var/log/emerge.log | cut -c1-10))/86400" | bc)
    p=$(wc -l < $i/tmp/packages)
    rp=$(echo "(19000-$p)/$d" | bc 2>/dev/null)
    [[ $e -lt 1000 ]] && rp=0
    echo -e "$e\t$d\t$p\t$rp\t$(basename $i)"
  done
  echo
}


function LastEmergeOperation()  {
  echo
  df -h |\
  grep 'img./' |\
  cut -f4-5 -d'/' |\
  while read i
  do
    printf "%s\r\t\t\t\t\t\t  " $(basename $i)
    tac ~/$i/var/log/emerge.log |\
    grep -m 1 -e "[>>>|***] emerge" |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' |\
    perl -wane 'chop ($F[0]); my @t = split (/\s+/, scalar localtime ($F[0])); print join (" ", $t[3], @F[1,3..$#F]), "\n"'
  done |\
  sort
  echo
}


function PackagesPerDay() {
  echo
  ls -1d ~/run/* |\
  while read i
  do
    printf "%s\r\t\t\t\t\t\t" $(basename $i)
    qlop -lC -f $i/var/log/emerge.log |\
    perl -wane '
      BEGIN { %h=(); $sum=0; $day=0; $old="" }
      { $sum++; my $cur=$F[2]; if ($old ne $cur) { $old=$cur; $day++ } $h{$day}++; }
      END { foreach my $k (sort { $a <=> $b } keys %h) { printf ("%5i", $h{$k}) } }
    '
    echo " "
  done
  echo
}


while getopts lop opt
do
  case $opt in
    l)  LastEmergeOperation
        ;;
    o)  Overall
        ;;
    p)  PackagesPerDay
        ;;
    *)  echo "call: $(basename $0) -o -l -p"
        exit 0
        ;;
  esac
done
