#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# https://github.com/containers/bubblewrap

function CreateCgroup() {
  local name=$cgdomain/${mnt##*/}

  # put all images under 1 sub group
  if [[ ! -d $cgdomain ]]; then
    # this is still racy
    if mkdir $cgdomain 2>/dev/null; then
      echo "+cpu +cpuset +memory" >$cgdomain/cgroup.subtree_control

      # 28 vCPU for all
      echo "$((28 * 100))" >$cgdomain/cpu.weight
      echo "$((28 * 100000)) 100000" >$cgdomain/cpu.max
      echo "96G" >$cgdomain/memory.max
      echo "192G" >$cgdomain/memory.swap.max # e.g. rust needs 15 GiB
    fi
  fi

  # previous cgroup entry is not yet reaped e.g. from setup process
  local i=10
  while [[ -d $name ]] && ((i--)); do
    sleep 0.25
  done
  if [[ -d $name ]]; then
    return 13
  fi
  if ! mkdir $name; then
    return 13
  fi
  echo "$$" >$name/cgroup.procs

  local jobs=$(sed 's,^.*j,,' $mnt/etc/portage/package.env/00jobs)
  if [[ ! $jobs =~ ^[0-9]+$ ]]; then
    echo " jobs is invalid: '$jobs', set to 1" >&2
    jobs=1
  fi

  # 1 vCPU per job
  echo "$((100 * jobs))" >$name/cpu.weight
  echo "$((100000 * jobs))" >$name/cpu.max

  # 2 GiB per job + a fixed amount for /var/tmp/portage
  echo "$((2 * jobs + 24))G" >$name/memory.max

  # swap
  echo "16G" >$name/memory.swap.max
}

function RemoveCgroup() {
  local name=$cgdomain/${mnt##*/}

  # still (but rarely) racy
  echo "while [[ -d $name ]]; do grep -q 'populated 0' $name/cgroup.events 2>/dev/null && rmdir $name 2>/dev/null || sleep 0.2; done" | at now 2>/dev/null
}

# no echo here
function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT

  if [[ -d $lock_dir ]]; then
    rmdir "$lock_dir"
  fi
  RemoveCgroup
  exit $rc
}

function Bwrap() {
  local sandbox=(env -i
    /usr/bin/bwrap
    --clearenv
    --setenv MAILTO "${MAILTO:-tinderbox}"
    --setenv PATH "/usr/sbin:/usr/bin:/sbin:/bin"
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
    if [[ -n ${SUDO_USER-} ]]; then
      "${sandbox[@]}" "-c" "su - $SUDO_USER"
    else
      "${sandbox[@]}"
    fi
  fi
}

#############################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

entrypoint=""
mnt=""
cgdomain=/sys/fs/cgroup/tb

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
lock_dir="/run/tb/${mnt##*/}.lock"

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

i=10
while [[ -d $lock_dir ]] && ((i--)); do
  sleep 0.25
done
if [[ -d $lock_dir ]]; then
  echo " lock dir '$lock_dir' exists" >&2
  exit 1
fi
trap 'Exit' INT QUIT TERM EXIT
mkdir -p "$lock_dir"

CreateCgroup
if [[ -n $entrypoint ]]; then
  rm -f "$mnt/root/entrypoint"
  cp "$entrypoint" "$mnt/root/entrypoint"
  chmod 744 "$mnt/root/entrypoint"

  rm -f "$mnt/root/lib.sh"
  cp "$(dirname $0)/lib.sh" "$mnt/root/lib.sh"
  chmod 644 "$mnt/root/lib.sh"
fi
Bwrap
