#!/bin/bash
# set -x


# bubblewrap (better chroot) into an image interactively - or - run a script in it


function Help() {
  echo
  echo "  call: $(basename $0) -m mountpoint [-s <entrypoint script>]"
  echo
}


function CgroupCreate() {
  local name=$1
  local pid=$2

  # use cgroup v1 if available
  if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
    return 0
  fi

  cgcreate -g cpu,memory:$name

  # limit each image having -jX in its name to X+0.1 cpus
  local j=$(grep -Eo '\-j[0-9]+' <<< $name | cut -c3-)
  if [[ -z $j ]]; then
    echo "got no value for -j , use 1"
    x=1
  elif [[ $j -gt 10 ]]; then
    echo "value for -j: $j , use 10"
    x=10
  else
    x=$j
  fi

  local quota=$((100000 * $x + 10000))
  cgset -r cpu.cfs_quota_us=$quota          $name
  cgset -r memory.limit_in_bytes=40G        $name
  cgset -r memory.memsw.limit_in_bytes=70G  $name

  for i in cpu memory
  do
    echo      1 > /sys/fs/cgroup/$i/$name/notify_on_release
    echo "$pid" > /sys/fs/cgroup/$i/$name/tasks
  done
}


function Cleanup()  {
  local rc=${1:-$?}

  rmdir "$lock_dir"

  exit $rc
}


function Exit()  {
  echo "bailing out ..."
  trap - INT QUIT TERM EXIT
}


#############################################################################
#
# main
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

trap Exit INT QUIT TERM EXIT

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

mnt=""
entrypoint=""

while getopts h\?m:s: opt
do
  case $opt in
    h|\?) Help
          ;;
    m)    if [[ -z "${OPTARG##*/}" || "$OPTARG" =~ [[:space:]] || "$OPTARG" =~ [\\\(\)\`$] ]]; then
            echo "argument not accepted"
            exit 2
          fi

          if [[ ! -e "$OPTARG" ]]; then
            echo "no valid mount point found"
            exit 2
          fi

          if [[ ! $(stat -c '%u' "$OPTARG") = "0" ]]; then
            echo "wrong ownership of mount point"
            exit 2
          fi

          mnt=$OPTARG
          ;;
    s)    if [[ ! -s "$OPTARG" ]]; then
            echo "no valid entry point script given: $OPTARG"
            exit 2
          fi
          entrypoint="$OPTARG"
          ;;
  esac
done

if [[ -z "$mnt" ]]; then
  echo "no mnt given!"
  exit 3
fi

lock_dir="/run/tinderbox/${mnt##*/}.lock"
if [[ -d $lock_dir ]]; then
  echo "found $lock_dir"
  exit 4
fi
mkdir -p "$lock_dir"
trap Cleanup QUIT TERM EXIT

sandbox=(env -i
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    HOME=/root
    SHELL=/bin/bash
    TERM=linux
    /usr/bin/bwrap
        --unshare-cgroup
        --unshare-ipc
        --unshare-pid
        --unshare-uts
        --hostname "$(cat ${mnt}/etc/conf.d/hostname)"
        --die-with-parent
        --setenv MAILTO "${MAILTO:-tinderbox}"
        --bind "$mnt"                             /
        --dev                                     /dev
        --mqueue                                  /dev/mqueue
        --perms 1777 --tmpfs                      /dev/shm
        --proc                                    /proc
        --tmpfs                                   /run
        --ro-bind ~tinderbox/tb/sdata/ssmtp.conf  /etc/ssmtp/ssmtp.conf
        --bind ~tinderbox/tb/data                 /mnt/tb/data
        --bind ~tinderbox/distfiles               /var/cache/distfiles
        --tmpfs                                   /var/tmp/portage
        --chdir /var/tmp/tb
        /bin/bash -l
)

CgroupCreate local/${mnt##*/} $$

if [[ -n "$entrypoint" ]]; then
  rm -f             "$mnt/entrypoint"
  cp "$entrypoint"  "$mnt/entrypoint"
  chmod 744         "$mnt/entrypoint"
  ("${sandbox[@]}" -c "/entrypoint")
else
  ("${sandbox[@]}")
fi
