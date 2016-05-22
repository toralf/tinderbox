#!/bin/sh
#
# set -x

mailto="tinderbox@zwiebeltoralf.de"

# notice, if emerge runs for longer than $1 second(s)
#
let max=${1:-8*3600}

pgrep -a emerge | grep -v -E ' @|--resume' |\
while read line
do
  pid=$(echo "$line" | cut -f1 -d" ")
  t=$(ps -p $pid -o etimes=)
  let t=t+0
  if [[ $t -gt $max ]]; then
    pstree -Usalnup $pid | mail -s "$(basename $0): process $pid runs since $t sec" $mailto
  fi
done

