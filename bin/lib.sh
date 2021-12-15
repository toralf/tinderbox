# list if locked and/or symlinked to ~run
function __list_images() {
  (
    ls ~tinderbox/run/                    | sort
    ls /run/tinderbox/ | sed 's,.lock,,g' | sort
  ) |\
  xargs -n 1 --no-run-if-empty basename  |\
  awk '!x[$0]++' |\
  while read -r i
  do
    ls -d ~tinderbox/run/${i} 2>/dev/null ||\
    ls -d ~tinderbox/img/${i} 2>/dev/null
  done
}


# $1:$2, eg. 1:5
function __dice() {
  [[ $(($RANDOM % $2)) -lt $1 ]]
}


# /run/ lock dir is used by bwrap and cgroup
function __is_running() {
  [[ -d /run/tinderbox/$(basename $1).lock ]]
}


function getStartTime() {
  cat ~tinderbox/img/$(basename $1)/var/tmp/tb/setup.timestamp
}

