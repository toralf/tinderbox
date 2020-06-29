#!/bin/bash
#
# set -x


# bubblewrap into an image interactively - or - run an entrypoint script


function Help() {
  echo
  echo "  call: $(basename $0) [-c] -m mountpoint [-s <entrypoint script>]"
  echo "  -c = put under Cgroup control"
  echo
}


function Cgroup() {
  # force an oom-killer before the kernel does it, eg. for dev-perl/GD or dev-lang/spidermonkey
  local cgdir="/sys/fs/cgroup/memory/local/${mnt##*/}"
  if [[ ! -d "$cgdir" ]]; then
    mkdir "$cgdir"
  fi

  echo "1"   > "$cgdir/memory.use_hierarchy"
  echo "20G" > "$cgdir/memory.limit_in_bytes"
  echo "30G" > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$$"  > "$cgdir/tasks"

  # restrict blast radius if -j1 is ignored
  local cgdir="/sys/fs/cgroup/cpu/local/${mnt##*/}"
  if [[ ! -d "$cgdir" ]]; then
    mkdir "$cgdir"
  fi
  echo "150000" > "$cgdir/cpu.cfs_quota_us"
  echo "100000" > "$cgdir/cpu.cfs_period_us"
  echo "$$"     > "$cgdir/tasks"
}


function Cleanup()  {
  rc=${1:-$?}
  rmdir "$lock_dir" && exit $rc || exit $?
}


function Exit()  {
  echo "bailing out ..."
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

trap Exit EXIT QUIT TERM

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

do_cgroup="no"
mnt=""
entrypoint=""
while getopts cm:s:h\? opt
do
  case $opt in
    c)  do_cgroup="yes"
        ;;
    h|\?)
        Help
        ;;
    m)
        if [[ "$OPTARG" =~ [[:space:]] || "$OPTARG" =~ '\' || "${OPTARG##*/}" = "" ]]; then
          echo "argument not accepted"
          exit 2
        fi

        for i in 1 2
        do
          mnt=/home/tinderbox/img${i}/${OPTARG##*/}
          if [[ -d "$mnt" ]]; then
            break
          fi
        done

        if [[ -z "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 || ! "$mnt" = "$(realpath $mnt)" ]]; then
          echo "mount point not accepted"
          exit 2
        fi
        ;;
    s)
        if [[ ! -f "$OPTARG" ]]; then
          echo "no valid entry point script given: $OPTARG"
          exit 3
        fi

        entrypoint="$OPTARG"
        ;;
  esac
done

if [[ -z "$mnt" ]]; then
  echo "no mnt given!"
  exit 4
fi

# a basic lock mechanism: only mkdir is an atomic kernel file system operation
lock_dir="/run/tinderbox/${mnt##*/}.lock"
mkdir "$lock_dir"

trap Cleanup EXIT QUIT TERM

if [[ -n "$entrypoint" ]]; then
  if [[ -L "$mnt/entrypoint" ]]; then
    echo "found symlinked $mnt/entrypoint"
    exit 4
  fi

  if [[ -e "$mnt/entrypoint" ]]; then
    rm -f "$mnt/entrypoint"
  fi
  touch             "$mnt/entrypoint"
  chmod 744         "$mnt/entrypoint"
  cp "$entrypoint"  "$mnt/entrypoint"
fi

sandbox=(env -i
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    HOME=/root
    SHELL=/bin/bash
    TERM=linux
    /usr/bin/bwrap
    --bind "$mnt"                       /
    --bind /home/tinderbox/tb/data      /mnt/tb/data
    --bind /home/tinderbox/distfiles    /var/cache/distfiles
    --ro-bind /home/tinderbox/tb/sdata  /mnt/tb/sdata
    --ro-bind /var/db/repos             /mnt/repos
    --tmpfs                             /var/tmp/portage
    --tmpfs /dev/shm
    --dev /dev
    --proc /proc
    --mqueue /dev/mqueue
    --unshare-cgroup
    --unshare-ipc
    --unshare-pid
    --unshare-user-try
    --unshare-uts
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /var/tmp/tb
    --die-with-parent
     /bin/bash -l
)

if [[ $do_cgroup = "yes" ]]; then
  Cgroup
fi

if [[ -n "$entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi
