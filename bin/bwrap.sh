#!/bin/bash
#
# set -x


# bubblewrap (better chroot) into an image interactively - or - run an entrypoint script


function Help() {
  echo
  echo "  call: $(basename $0) -m mountpoint [-s <entrypoint script>]"
  echo
}


function CgroupCreate() {
  # force an oom-killer before the kernel decides what to kill
  cgcreate -g memory:/local/${mnt##*/}
  cgset -r memory.use_hierarchy=1 -r memory.limit_in_bytes=20G -r memory.memsw.limit_in_bytes=30G -r memory.tasks=$$ ${mnt##*/}

  # restrict blast radius if -j1 is ignored
  cgcreate -g cpu:/local/${mnt##*/}
  cgset -r cpu.cfs_quota_us=150000 -r cpu.cfs_period_us=100000 -r cpu.tasks=$$ ${mnt##*/}
}


function CgroupDelete() {
  cgdelete -g cpu:/local/${mnt##*/}
  cgdelete -g memory:/local/${mnt##*/}
}


function Cleanup()  {
  rc=${1:-$?}
  CgroupDelete
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

mnt=""
entrypoint=""
while getopts h\?m:s: opt
do
  case $opt in
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

CgroupCreate
if [[ -n "$entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi
