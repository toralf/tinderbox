#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function CreateCgroup() {
  local name=$cgdomain/${mnt##*/}
  local cpu

  # put all tinderbox images under 1 sub group
  if [[ ! -d $cgdomain ]]; then
    if mkdir $cgdomain 2>/dev/null; then
      echo "+cpu +cpuset +memory" >$cgdomain/cgroup.subtree_control

      # reserve n vCPU for non-tinderboxing tasks
      cpu=$(($(nproc) - 4))
      echo "$((cpu * 100))" >$cgdomain/cpu.weight
      echo "$((cpu * 100000))" >$cgdomain/cpu.max
      echo "110G" >$cgdomain/memory.max
      echo "200G" >$cgdomain/memory.swap.max
    fi
  fi

  if [[ -d $name ]]; then
    # old cgroup entry (e.g. from the preceding setup) might not yet been reaped
    local i=10
    while [[ -d $name ]] && ((i--)); do
      sleep 0.25
    done
    if [[ -d $name ]]; then
      return 12
    fi
  fi

  if ! mkdir $name; then
    return 13
  fi
  echo "$$" >$name/cgroup.procs

  # vCPU and memory per image, the cpu value should match dev-build/steve
  cpu=10
  echo "$((cpu * 100))" >$name/cpu.weight
  echo "$((cpu * 100000))" >$name/cpu.max
  echo "64G" >$name/memory.max
  echo "64G" >$name/memory.swap.max
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
    RemoveCgroup
    rmdir $lock_dir
  fi
  rm -f /tmp/$(basename $mnt).json
  exit $rc
}

function Bwrap() {
  local sandbox=(env -i
    /usr/bin/bwrap
    --clearenv
    --setenv HOME "/root"
    --setenv MAILTO "$(<$(dirname $0)/../sdata/mailto)"
    --setenv PATH "/usr/sbin:/usr/bin:/sbin:/bin"
    --setenv SHELL "/bin/bash"
    --setenv TERM "linux"
    --setenv USER "root"
    --hostname "$(<$mnt/etc/conf.d/hostname)"
    --level-prefix
    --unshare-cgroup
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --bind "$mnt" /
    --dev /dev
    --dev-bind /dev/console /dev/console
    --dev-bind /dev/steve /dev/steve
    --mqueue /dev/mqueue
    --perms 1777 --tmpfs /dev/shm
    --proc /proc
    --perms 0755 --tmpfs /run
    --ro-bind /sys /sys
    --size $((2 ** 30)) --perms 1777 --tmpfs /tmp
    --bind ~tinderbox/distfiles /var/cache/distfiles
    --ro-bind ~tinderbox/tb/data /mnt/tb/data
    --bind ~tinderbox/tb/findings /mnt/tb/findings
    --ro-bind "$(dirname $0)/../sdata/msmtprc" /etc/msmtprc
    --ro-bind "$(dirname $0)/../sdata/ssmtp.conf" /etc/ssmtp/ssmtp.conf
    --ro-bind ~tinderbox/.bugzrc /root/.bugzrc
    --info-fd 11
  )
  if ! grep -q -F " -g " $mnt/etc/portage/make.conf; then
    sandbox+=(--size $((32 * 2 ** 30)) --perms 1777 --tmpfs /var/tmp/portage)
  fi
  if [[ -n $entrypoint ]]; then
    sandbox+=(--new-session)
  fi

  sandbox+=(/bin/bash -l)
  {
    if [[ -n $entrypoint ]]; then
      "${sandbox[@]}" "-c" "/root/entrypoint"
    else
      if [[ -n ${SUDO_USER-} ]]; then
        "${sandbox[@]}" "-c" "su - $SUDO_USER"
      else
        "${sandbox[@]}"
      fi
    fi
  } 11>/tmp/$(basename $mnt).json
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

while getopts e:m: opt; do
  case $opt in
  e)
    if [[ ! -s $OPTARG || $OPTARG =~ [[:space:]] || $OPTARG =~ [\\\(\)\`$] ]]; then
      echo " no valid entrypoint script given" >&2
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

cgdomain=/sys/fs/cgroup/tb
lock_dir="/run/tb/${mnt##*/}.lock"

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

  if [[ $entrypoint == $(dirname $0)/job.sh ]]; then
    rm -f "$mnt/root/lib.sh"
    cp "$(dirname $0)/lib.sh" "$mnt/root/lib.sh"
    chmod 644 "$mnt/root/lib.sh"
  fi
fi
Bwrap
