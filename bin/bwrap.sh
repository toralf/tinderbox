#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# much better than chroot: https://github.com/containers/bubblewrap

function CreateCgroup() {
  local name=/local/tb/${1?}
  local pid=${2?}

  local i=0
  while [[ $(cgget -g cpu,memory:$name | wc -l) -gt 2 ]]; do
    ((++i))
    echo -n " cgroup '$name' does already exist, " >&2
    if [[ $i -gt 5 ]]; then
      echo "giving up" >&2
      return 1
    fi
    echo "waiting" >&2
    sleep 1
  done

  if ! cgcreate -g cpu,memory:$name; then
    return 1
  fi

  for i in cpu memory; do
    echo "1" >/sys/fs/cgroup/$i/$name/notify_on_release
    if ! echo "$pid" >/sys/fs/cgroup/$i/$name/tasks; then
      return 1
    fi
  done

  local jobs
  jobs=$(sed 's,^.*j,,' $mnt/etc/portage/package.env/00jobs)

  if [[ ! $jobs =~ ^[0-9]+$ ]]; then
    echo " 'jobs' is invalid: '$jobs'" >&2
    return 1
  fi

  # jobs+0.1 vCPU, slice is 10us
  local cpu=$((100000 * jobs + 10000))
  cgset -r cpu.cfs_quota_us=$cpu $name

  # 2 GiB per build job + xx for /var/tmp/portage (being a tmpfs)
  local mem=$((2 * jobs + 20))
  cgset -r memory.limit_in_bytes=${mem}G $name

  # memory+swap, add a safety limit
  cgset -r memory.memsw.limit_in_bytes=$((mem + 16))G $name
}

# no "echo" here
function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT
  if [[ -d $lock_dir ]]; then
    rm -r -- "$lock_dir"
  fi
  exit $rc
}

function Bwrap() {
  local path="/usr/sbin:/usr/bin"
  if [[ ! $mnt =~ "merged_usr" && ! $mnt =~ "23.0" ]]; then
    path+="/sbin:/bin"
  fi

  local sandbox=(env -i
    /usr/bin/bwrap
    --clearenv
    --setenv MAILTO "${MAILTO:-tinderbox}"
    --setenv PATH "$path"
    --setenv SHELL "/bin/bash"
    --setenv TERM "linux"
    --hostname "$(cat $mnt/etc/conf.d/hostname)"
    --unshare-cgroup
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --bind "$mnt" /
    --dev /dev
    --dev-bind /dev/console /dev/console
    --mqueue /dev/mqueue
    --perms 1777 --tmpfs /dev/shm
    --proc /proc
    --tmpfs /run
    --ro-bind /sys /sys
    --size $((2 ** 30)) --perms 1777 --tmpfs /tmp
    --size $((2 ** 35)) --perms 1777 --tmpfs /var/tmp/portage
    --bind ~tinderbox/distfiles /var/cache/distfiles
    --ro-bind ~tinderbox/tb/data /mnt/tb/data
    --bind ~tinderbox/tb/findings /mnt/tb/findings
    --setenv HOME "/root"
    --setenv USER "root"
    --ro-bind "$(dirname $0)/../sdata/ssmtp.conf" /etc/ssmtp/ssmtp.conf
    --ro-bind ~tinderbox/.bugzrc /root/.bugzrc
  )
  if [[ -n $entrypoint ]]; then
    sandbox+=(--new-session)
  fi
  sandbox+=(/bin/bash -l)

  if [[ -n $entrypoint ]]; then
    "${sandbox[@]}" "-c" "/root/entrypoint"
  else
    "${sandbox[@]}"
  fi
}

#############################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

trap Exit INT QUIT TERM EXIT

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

entrypoint=""
mnt=""

while getopts e:m: opt; do
  case $opt in
  e)
    if [[ ! -s $OPTARG ]]; then
      echo " no valid entrypoint script given: $OPTARG" >&2
      exit 1
    fi
    entrypoint=$OPTARG
    ;;
  m)
    if [[ -z $OPTARG || -z ${OPTARG##*/} || $OPTARG =~ [[:space:]] || $OPTARG =~ [\\\(\)\`$] ]]; then
      echo " mount point not accepted" >&2
      exit 1
    fi
    mnt=~tinderbox/img/${OPTARG##*/}
    ;;
  *)
    echo " unknown parameter '$opt'" >&2
    exit 1
    ;;
  esac
done
lock_dir="/run/tinderbox/${mnt##*/}.lock"

if [[ -z $entrypoint && -n ${SUDO_USER-} ]]; then
  echo " non-root interactive login is not allowed" >&2
  exit 1
fi

if [[ -z $mnt ]]; then
  echo " mount point is empty" >&2
  exit 1
fi

if [[ ! -e $mnt ]]; then
  echo " no valid mount point given" >&2
  exit 1
fi

if [[ $(stat -c '%u' "$mnt") != "0" ]]; then
  echo " wrong ownership of mount point" >&2
  exit 1
fi

if [[ -d $lock_dir ]]; then
  echo " lock dir '$lock_dir' does already exist" >&2
  exit 1
fi
mkdir -p "$lock_dir"

CreateCgroup ${mnt##*/} $$
if [[ -n $entrypoint ]]; then
  rm -f "$mnt/root/entrypoint"
  cp "$entrypoint" "$mnt/root/entrypoint"
  chmod 744 "$mnt/root/entrypoint"

  rm -f "$mnt/root/lib.sh"
  cp "$(dirname $0)/lib.sh" "$mnt/root/lib.sh"
  chmod 644 "$mnt/root/lib.sh"
fi

Bwrap
