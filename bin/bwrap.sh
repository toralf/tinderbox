#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# much better than chroot: https://github.com/containers/bubblewrap

function CgroupCreate() {
  local name=/local/tb/${1?}
  local pid=${2?}

  if ! cgcreate -g cpu,memory:$name; then
    return 1
  fi

  for i in cpu memory; do
    echo "1" >/sys/fs/cgroup/$i/$name/notify_on_release
    if ! echo "$pid" >/sys/fs/cgroup/$i/$name/tasks; then
      return 1
    fi
  done

  local jobs=$(sed 's,^.*j,,' $mnt/etc/portage/package.env/00jobs)

  # jobs+0.1 vCPU, slice is 10us
  local cpu=$((100000 * jobs + 10000))
  cgset -r cpu.cfs_quota_us=$cpu $name

  # 2 GB per build job + xx for /var/tmp/portage (being a tmpfs)
  local mem=$((2 * jobs + 20))
  cgset -r memory.limit_in_bytes=${mem}G $name

  # memory+swap, add another safety limit, host system has 256 GB swap at all
  cgset -r memory.memsw.limit_in_bytes=$((mem + 16))G $name
}

# no "echo" here
function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT

  if [[ -d $lock_dir ]]; then
    rm -r -- $lock_dir
  else
    echo " no lock dir $lock_dir found" >&2
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
    --setenv HOME "/root"
    --setenv MAILTO "${MAILTO:-tinderbox}"
    --setenv PATH "$path"
    --setenv SHELL "/bin/bash"
    --setenv TERM "linux"
    --setenv USER "root"
    --hostname "$(cat $mnt/etc/conf.d/hostname)"
    --die-with-parent
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
    --ro-bind /run/tinderbox /run/tinderbox
    --size $((2 ** 30)) --perms 1777 --tmpfs /tmp
    --size $((2 ** 35)) --perms 1777 --tmpfs /var/tmp/portage
    --ro-bind "$(dirname $0)/../sdata/ssmtp.conf" /etc/ssmtp/ssmtp.conf
    --ro-bind ~tinderbox/.bugzrc /root/.bugzrc
    --bind ~tinderbox/distfiles /var/cache/distfiles
    --ro-bind ~tinderbox/tb/data /mnt/tb/data
    --bind ~tinderbox/tb/findings /mnt/tb/findings
    /bin/bash -l
  )

  if [[ -n $entrypoint ]]; then
    ("${sandbox[@]}" -c "/root/entrypoint")
  else
    ("${sandbox[@]}" -c "su - ${SUDO_USER:-root}")
  fi
  local rc=$?

  return $rc
}

#############################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

export CGROUP_LOGLEVEL=ERROR

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

if [[ ! -d /run/tinderbox/ ]]; then
  mkdir /run/tinderbox/
fi

# this is the 1st barrier (the 2nd is that a cgroup can be created)
lock_dir="/run/tinderbox/${mnt##*/}.lock"
if ! mkdir "$lock_dir"; then
  echo " lock dir cannot be created: $lock_dir" >&2
  exit 1
fi

trap Exit INT QUIT TERM EXIT
CgroupCreate ${mnt##*/} $$
if [[ -n $entrypoint ]]; then
  rm -f "$mnt/root/entrypoint"
  cp "$entrypoint" "$mnt/root/entrypoint"
  chmod 744 "$mnt/root/entrypoint"

  rm -f "$mnt/root/lib.sh"
  cp "$(dirname $0)/lib.sh" "$mnt/root/lib.sh"
  chmod 644 "$mnt/root/lib.sh"
fi

Bwrap
