# either locked or in ~run
function __list_images() {
  (
    ls /run/tinderbox/ | sed 's,.lock,,g' | sort
    ls ~tinderbox/run/                    | sort
  ) |\
  xargs -n 1 basename |\
  awk '!x[$0]++' |\
  while read -r i
  do
    ls -d ~tinderbox/run/${i} 2>/dev/null ||\
    ls -d ~tinderbox/img/${i} 2>/dev/null
  done |\
  cat
}


# n:N, eg. 1:5
function __dice() {
  local n=$1
  local N=$2
  [[ $(($RANDOM % N)) -lt $n ]]
}


# lock dir is handled by bwrap and cgroup agent
function __is_running() {
  [[ -d "/run/tinderbox/${1##*/}.lock" ]]
}
