#!/bin/bash
#
# set -x

# setup a new tinderbox image

#############################################################################
#
# functions

# helper of ThrowUseFlags()
#
function DropUseFlags()  {
  egrep -v -e '32|64|^armv|bindist|bootstrap|build|cdinstall|compile-locales|consolekit|debug|elogind|forced-sandbox|gallium|gcj|ghcbootstrap|hardened|hostname|ithreads|kill|libav|libreoffice|libressl|libunwind|linguas|make-symlinks|malloc|minimal|monolithic|multilib|musl|nvidia|oci8|opencl|openmp|openssl|pax|perftools|prefix|tools|selinux|split-usr|static|symlink|system|systemd|test|uclibc|vaapi|vdpau|vim-syntax|vulkan'
}


function SelectUseFlags() {
  n=${1:-1}
  m=${2:-0}

  # throw up to n-1
  #
  shuf -n $(($RANDOM % $n)) | sort |\
  while read flag
  do
    # mask about 1/m
    #
    if [[ $m -gt 0 && $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-"
    fi
    echo -n "$flag "
  done
}


function PrintUseFlags() {
  xargs -s 78 | sed 's/^/  /g'
}


function ThrowUseFlags()  {
  # local USE flags
  #
  grep -h 'flag name="' $repo_gentoo/*/*/metadata.xml |\
  cut -f2 -d'"' -s | sort -u |\
  DropUseFlags |\
  SelectUseFlags 50 7 |\
  PrintUseFlags

  echo

  # global USE flags
  #
  grep -v -e '^$' -e '^#' $repo_gentoo/profiles/use.desc |\
  cut -f1 -d ' ' -s |\
  DropUseFlags |\
  SelectUseFlags 40 7 |\
  PrintUseFlags
}


# helper of SetOptions()
#
function ShuffleProfile() {
  eselect profile list |\
  awk ' { print $2 } ' |\
  grep -e "^default/linux/amd64/17\.1" -e "^default/linux/amd64/17\../musl" |\
  grep -v -e '/x32' -e '/selinux' -e '/uclibc' |\
  cut -f4- -d'/' -s |\
  shuf
}


# helper of main()
# will be overwritten by command line parameter if given
#
function SetOptions() {
  autostart="y"               # start the image after setup
  origin=""                   # derive settings from this image
  useflags="ThrowUseFlags"

  # throw a profile and prefer a non-running one, but the last entry in input will make it eventually
  #
  while read profile
  do
    ls -d ~tinderbox/run/$(echo $profile | tr '/' '_')-* &>/dev/null || break
  done < <(ShuffleProfile)

  features="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox cgroup -news protect-owned -collision-protect"

  # check almost unstable
  #
  keyword="unstable"

  # parity: OpenSSL : LibreSSL = 1:1
  #
  libressl="n"
  if [[ "$keyword" = "unstable" ]]; then
    if [[ $(($RANDOM % 2)) -eq 0 ]]; then
      libressl="y"
    fi
  fi

  # a "y" vields to ABI_X86="32 64" in make.conf
  #
  multilib="n"
  if [[ ! $profile =~ "/no-multilib" ]]; then
    # run at most 1 image at a a time
    #
    if [[ -z "$(ls -d ~tinderbox/run/*abi32+64* 2>/dev/null)" ]]; then
      if [[ $(($RANDOM % 16)) -eq 0 ]]; then
        multilib="y"
      fi
    fi
  fi

  #  FEATURES=test
  #
  testfeature="n"
  if [[ "$keyword" = "unstable" ]]; then
    # run at most 1 image at a a time
    #
    if [[ -z "$(ls -d ~tinderbox/run/*test* 2>/dev/null)" ]]; then
      if [[ $(($RANDOM % 4)) -eq 0 ]]; then
        testfeature="y"
      fi
    fi
  fi

  musl="n"
  if [[ $profile =~ "/musl" ]]; then
    musl="y"

    keyword="unstable"
    libressl="n"
    multilib="n"
    testfeature="n"
  fi

}


# helper of CheckOptions()
#
function checkBool()  {
  var=$1
  val=$(eval echo \$${var})

  if [[ "$val" != "y" && "$val" != "n" ]]; then
    echo " wrong value for variable \$$var: >>$val<<"
    exit 1
  fi
}


# helper of main()
#
function CheckOptions() {
  if [[ -z "$profile" ]]; then
    echo " profile empty!"
    exit 1
  fi

  if [[ ! -d $repo_gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: >>$profile<<"
    exit 1
  fi

  if [[ "$keyword" != "stable" && "$keyword" != "unstable" ]]; then
    echo " wrong value for \$keyword: >>$keyword<<"
    exit 1
  fi

  checkBool "autostart"
  checkBool "libressl"
  checkBool "multilib"
  checkBool "testfeature"
  checkBool "musl"
}


# helper of UnpackStage3()
#
function ComputeImageName()  {
  name="$(echo $profile | tr '/' '_')-"

  if [[ "$keyword" = "stable" ]]; then
    name="${name}_stable"
  fi

  if [[ "$libressl" = "y" ]]; then
    name="${name}_libressl"
  fi

  if [[ "$multilib" = "y" ]]; then
    name="${name}_abi32+64"
  fi

  if [[ "$testfeature" = "y" ]]; then
    name="${name}_test"
  fi

  if [[ "$musl" = "y" ]]; then
    name="${name}_musl"
  fi

  name="$(echo $name | sed -e 's/-[_-]/-/g' -e 's/-$//')"
}


function CreateImageDir() {
  cd $(readlink ~tinderbox/img) || exit 1
  name="${name}-$(date +%Y%m%d-%H%M%S)"
  mkdir $name || exit 1

  # relative path (eg ./img1) to ~tinderbox
  #
  mnt=$(readlink ../img)/$name

  echo " new image: $mnt"
  echo
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  latest="$tbdistdir/latest-stage3.txt"

  for mirror in $gentoo_mirrors
  do
    wgeturl="$mirror/releases/amd64/autobuilds"
    wget --quiet $wgeturl/latest-stage3.txt --output-document=$latest && break
    echo "mirror failed: $mirror, trying next ..."
  done

  case $profile in
    */no-multilib/hardened)
      stage3=$(grep "/hardened/stage3-amd64-hardened+nomultilib-20.*\.tar\." $latest)
      ;;

    */hardened)
      stage3=$(grep "/hardened/stage3-amd64-hardened-20.*\.tar\." $latest)
      ;;

    */no-multilib)
      stage3=$(grep "/stage3-amd64-nomultilib-20.*\.tar\." $latest)
      ;;

    */systemd)
      stage3=$(grep "/systemd/stage3-amd64-systemd-20.*\.tar\." $latest)
      ;;

    */musl/hardened)
      stage3=$(grep "/musl/stage3-amd64-musl-hardened-20.*\.tar\." $latest)
      ;;

    */musl)
      stage3=$(grep "/musl/stage3-amd64-musl-vanilla-20.*\.tar\." $latest)
      ;;

    *)
      stage3=$(grep "/stage3-amd64-20.*\.tar\." $latest)
      ;;
  esac
  stage3=$(echo $stage3 | cut -f1 -d' ' -s)

  if [[ -z "$stage3" ]]; then
    echo "can't get stage3 filename for profile '$profile' in $latest"
    exit 1
  fi

  f=$tbdistdir/${stage3##*/}
  if [[ ! -s $f || ! -f $f.DIGESTS.asc ]]; then
    date
    echo "downloading $stage3 ..."
    wget --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$tbdistdir
    rc=$?
    echo
    if [[ $rc -ne 0 ]]; then
      echo " can't download stage3 file '$stage3', rc=$rc"
      rm $f{,.DIGESTS.asc}
      exit 1
    fi
  fi

  # do this once before for each key:
  #
  # gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys <key>
  # gpg --edit-key <key>
  # and set "trust" to 5 (==ultimately)
  #
  date
  gpg --quiet --refresh-keys releng@gentoo.org
  gpg --quiet --verify $f.DIGESTS.asc || exit 1
  echo

  date
  cd $name
  echo " untar'ing $f ..."
  tar -xf $f --xattrs --exclude='./dev/*' || exit 1
  echo
}


# configure remote (bind mounted, see chr.sh) and image specific repositories
#
function CompileRepoFiles()  {
  mkdir -p ./etc/portage/repos.conf/

  # this is synced explicitely in job.sh via a rsync call to the local host directory
  #
  cat << EOF > ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location = $repo_gentoo

EOF

  # this is used directly and not rsynced
  #
  cat << EOF > ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location = /mnt/tb/data/portage

EOF

  # this is an image specific rarely used local repository
  #
  mkdir -p                  ./$repo_local/{metadata,profiles}
  echo 'masters = gentoo' > ./$repo_local/metadata/layout.conf
  echo 'local'            > ./$repo_local/profiles/repo_name

  cat << EOF > ./etc/portage/repos.conf/local.conf
[local]
location = $repo_local

EOF

  cat << EOF > ./etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo
auto-sync = no

[gentoo]
priority = 10

[tinderbox]
priority = 90

[local]
priority = 99

EOF

  if [[ "$libressl" = "y" ]]; then
    cat << EOF > ./etc/portage/repos.conf/libressl.conf
[libressl]
location = $repo_libressl

EOF

  cat << EOF >> ./etc/portage/repos.conf/default.conf
[libressl]
priority = 20

EOF

  fi

  if [[ "$musl" = "y" ]]; then
    cat << EOF > ./etc/portage/repos.conf/musl.conf
[musl]
location = $repo_musl

EOF
  cat << EOF >> ./etc/portage/repos.conf/default.conf
[musl]
priority = 30

EOF
  fi
}


# compile make.conf
#
function CompileMakeConf()  {
  # throw up to 10 languages
  #
  if [[ -n "$origin" && -e $origin/etc/portage/make.conf ]]; then
    l10n=$(grep "^L10N=" $origin/etc/portage/make.conf | cut -f2- -d'=' -s | tr -d '"')
  else
    l10n="$(grep -v -e '^$' -e '^#' $repo_gentoo/profiles/desc/l10n.desc | cut -f1 -d' ' | shuf -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  touch ./etc/portage/make.conf.USE

  cat << EOF > ./etc/portage/make.conf
LC_MESSAGES=C

COMMON_FLAGS="-O2 -pipe -march=native -fno-common -falign-functions=32:25:16"  # test gcc-10 + bug 685160
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

source /etc/portage/make.conf.USE
USE="\${USE}

  ssp -cdinstall -oci8 -pax_kernel -valgrind -symlink
"

$([[ ! $profile =~ "hardened" ]] && echo 'PAX_MARKINGS="none"')
$([[ "$multilib" = "y" ]] && echo 'ABI_X86="32 64"')
ACCEPT_KEYWORDS=$([[ "$keyword" = "unstable" ]] && echo '"~amd64"' || echo '"amd64"')
ACCEPT_LICENSE="* -@EULA"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

FEATURES="$features"
EMERGE_DEFAULT_OPTS="--with-bdeps=y --verbose-conflicts --nospinner --tree --quiet-build --autounmask-keep-masks=y --complete-graph=y --verbose --color=n --autounmask=n"
CLEAN_DELAY=0
NOCOLOR=yes

L10N="$l10n"
VIDEO_CARDS="dummy"

DISTDIR="/var/cache/distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="$gentoo_mirrors"

QEMU_SOFTMMU_TARGETS="x86_64 i386"
QEMU_USER_TARGETS="\$QEMU_SOFTMMU_TARGETS"

LLVM_TARGETS="X86"

EOF
  # the "tinderbox" user have to be put in group "portage" to make this effective
  #
  chgrp portage ./etc/portage/make.conf{,.USE}
  chmod g+w ./etc/portage/make.conf{,.USE}
}


# helper of CompilePortageFiles()
#
function cpconf() {
  for f in $*
  do
    # eg.: .../package.unmask.00stable -> package.unmask/00stable
    #
    to=$(sed 's,.00,/00,' <<< ${f##*/})
    cp $f ./etc/portage/$to
  done
}


# create portage + tinderbox directories + files and symlinks
#
function CompilePortageFiles()  {
  mkdir -p ./mnt/{repos,tb/data,tb/sdata} ./var/tmp/{portage,tb} ./var/cache/distfiles

  chgrp portage ./var/tmp/tb
  chmod ug+rwx  ./var/tmp/tb

  for d in package.{accept_keywords,env,mask,unmask,use} env
  do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir       ./etc/portage/$d
    fi
    chmod 775     ./etc/portage/$d
    chgrp portage ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../mnt/tb/data/patches)

  touch       ./etc/portage/package.mask/self     # contains failed packages of this image
  chmod a+rw  ./etc/portage/package.mask/self

  echo 'FEATURES="test"'                          > ./etc/portage/env/test
  echo 'FEATURES="-test"'                         > ./etc/portage/env/notest

  # to preserve the same dep tree re-try a failed package with +test again but ignore the test result in the 2nd run
  #
  echo 'FEATURES="test-fail-continue"'            > ./etc/portage/env/test-fail-continue

  # re-try failing packages w/o sandbox'ing
  #
  echo 'FEATURES="-sandbox -usersandbox"'         > ./etc/portage/env/nosandbox

  # re-try failing packages w/o CFLAGS quirk
  #
  cat <<EOF                                       > ./etc/portage/env/cflags_default
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

EOF

  # no parallel build
  #
  cat << EOF                                      > ./etc/portage/env/noconcurrent
EGO_BUILD_FLAGS="-p 1"
GO19CONCURRENTCOMPILATION=0
GOMAXPROCS="1"
MAKEOPTS="-j1"
NINJAFLAGS="-j1"
OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=1
RUSTFLAGS="-C codegen-units=1"
RUST_TEST_THREADS=1
RUST_TEST_TASKS=1

EOF

  echo '*/* noconcurrent'       > ./etc/portage/package.env/00noconcurrent
  echo "*/* $(cpuid2cpuflags)"  > ./etc/portage/package.use/00cpuflags

  if [[ $profile =~ '/systemd' ]]; then
    cpconf ~tinderbox/tb/data/package.*.00systemd
  fi

  cpconf ~tinderbox/tb/data/package.*.00common
  cpconf ~tinderbox/tb/data/package.*.00$keyword

  if [[ "$libressl" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.env.00libressl
  fi

  if [[ "$multilib" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.00abi32+64
  fi

  if [[ "$testfeature" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.00*test
  else
    # squash IUSE=+test
    #
    echo "*/* notest" > ./etc/portage/package.env/00notest
  fi

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}


function CompileMiscFiles()  {
  echo $name > ./var/tmp/tb/name

  # use local host DNS resolver
  #
  cat << EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1

EOF

  h=$(hostname)
  cat << EOF > ./etc/hosts
127.0.0.1 localhost $h.localdomain $h
::1       localhost $h.localdomain $h

EOF

  # avoid interactive question in vim
  #
  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0

EOF
}


# /var/tmp/tb/backlog.upd : update_backlog.sh writes to it
# /var/tmp/tb/backlog     : filled by setup_img.sh
# /var/tmp/tb/backlog.1st : filled by setup_img.sh, job.sh and retest.sh write to it
#
function CreateBacklog()  {
  bl=./var/tmp/tb/backlog

  truncate -s 0           $bl{,.1st,.upd}
  chmod 664               $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}

  # sort is needed if more than one repository is configured
  #
  qsearch --all --nocolor --name-only --quiet | sort -u | shuf >> $bl

  if [[ -e $origin && -s $origin/var/tmp/tb/task.history ]]; then
    # no replay of @sets or %commands
    # a replay of 'qlist -ICv' is intentionally not wanted
    #
    echo "INFO finished replay of task history of $origin"            >> $bl.1st
    grep -v -E "^(%|@)" $origin/var/tmp/tb/task.history | uniq | tac  >> $bl.1st
    echo "INFO starting replay of task history of $origin"            >> $bl.1st
  fi

  # update @world before working on the arbitrarily choosen package list
  # @system is just a fall back if @world stucks or takes too long
  # this is the last time where depclean is run w/o "-p" (and must succeeded)
  #
  cat << EOF >> $bl.1st
%emerge --depclean
@system
@world
EOF

  # whissi: this is a mysql alternative engine
  #
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    echo "dev-db/percona-server" >> $bl.1st
  fi

  # switch to LibreSSL
  #
  if [[ "$libressl" = "y" ]]; then
    # fetch crucial packages which must either be (re-)build or do act as a fallback;
    # hint: unmerge already schedules a @preserved-rebuild but nevertheless
    # the final @preserved-rebuild must not fail, therefore "% ..."
    #
    cat << EOF >> $bl.1st
%emerge @preserved-rebuild
%emerge --unmerge openssl
%emerge --fetchonly dev-libs/libressl net-misc/openssh net-misc/wget
%chgrp portage /etc/portage/package.use/00libressl
%cp /mnt/tb/data/package.use.00libressl /etc/portage/package.use/00libressl
EOF
  fi

  # at least systemd and virtualbox need (compiled) kernel sources and would fail in @preserved-rebuild otherwise
  #
  echo "%emerge -u sys-kernel/gentoo-sources" >> $bl.1st
  # upgrade GCC asap, but do not rebuild the existing one
  #
  if [[ $musl = "n" && $keyword = "unstable" ]]; then
    #   %...      : bail out if it fails
    #   =         : do not upgrade the current (slotted) version
    # dev-libs/*  : avoid a rebuild of GCC later in @system
    #
    echo "%emerge -u =$(ACCEPT_KEYWORDS="~amd64" portageq best_visible / sys-devel/gcc) dev-libs/mpc dev-libs/mpfr" >> $bl.1st
  else
    echo "sys-devel/gcc" >> $bl.1st     # rarely but possible to have a newer GCC version than the stage3 does have
  fi

  if [[ $profile =~ "systemd" ]]; then
    echo "%systemd-machine-id-setup" >> $bl.1st
  fi

  # sometimes Python was updated as a dep during setup
  #
  echo "%eselect python update" >> $bl.1st
}


# - configure locale, timezone etc.
# - install and configure tools called in job.sh using the "minimal" profile:
#     <package>                   <command/s>
#     mail-*                      MTA + mailx
#     app-arch/sharutils          uudecode
#     app-portage/gentoolkit      equery eshowkw revdep-rebuild
#     app-portage/portage-utils   qatom qlop
#     www-client/pybugz           bugz
# - dry run of @system using the desired profile
#
function CreateSetupScript()  {
  cat << EOF > ./var/tmp/tb/setup.sh || exit 1
#!/bin/sh
#
# set -x

rsync -aC /mnt/repos/gentoo /var/db/repos/
if [[ $libressl = "y" ]]; then
  rsync -aC /mnt/repos/libressl /var/db/repos/
fi
if [[ $musl = "y" ]]; then
  rsync -aC /mnt/repos/musl /var/db/repos/
fi

if [[ $musl = "y" ]]; then
  eselect profile set --force default/linux/amd64/$profile            || exit 1
else
  # use the base profile during setup to minimize dep graph
  #
  if [[ $profile =~ "/no-multilib" ]]; then
    eselect profile set --force default/linux/amd64/17.1/no-multilib  || exit 1
  else
    eselect profile set --force default/linux/amd64/17.1              || exit 1
  fi
fi

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data || exit 1

cat << 2EOF >> /etc/locale.gen

# by $0 at $(date)
#
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8

2EOF

if [[ ! $musl = "y" ]]; then
  locale-gen -j1 || exit 1
  eselect locale set en_US.UTF-8
fi

echo "$name" > /etc/conf.d/hostname

env-update
source /etc/profile

useradd -u $(id -u tinderbox) tinderbox

# ssmtp first to avoid that mailx pulls in another MTA
#
emerge -u mail-mta/ssmtp     || exit 1
emerge -u mail-client/mailx  || exit 1

emerge -u sys-apps/portage   || exit 1
emerge -u app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 1

if [[ $musl = "y" ]]; then
  cd /usr/lib && ln -s ../../usr/lib64/liblockfile.so.1       # needed for mailx to work
else
  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    # testing sys-libs/libxcrypt[system]
    #
    echo '=virtual/libcrypt-2*'         >> /etc/portage/package.unmask/libxcrypt

    echo '
    sys-libs/glibc      -crypt
    sys-libs/libxcrypt  compat static-libs system
    virtual/libcrypt    static-libs
    '                                   >> /etc/portage/package.use/libxcrypt

    echo 'sys-libs/glibc     -crypt'    >> /etc/portage/make.profile/package.use.force
    echo 'sys-libs/libxcrypt -system'   >> /etc/portage/make.profile/package.use.mask
  fi

  # glibc-2.31 + python-3 dep issue
  #
  emerge -1u virtual/libcrypt || exit 1
fi

# finally switch to the choosen profile
#
eselect profile set --force default/linux/amd64/$profile || exit 1

if [[ $testfeature = "y" ]]; then
  sed -i -e 's/FEATURES="/FEATURES="test /g' /etc/portage/make.conf
fi

# prefer compile/build tests over dep issue catching etc.
#
if [[ $testfeature = "y" || $multilib = "y" || $musl = "y" ]]; then
  touch /var/tmp/tb/KEEP
fi

# symlink credential files of mail-mta/ssmtp and www-client/pybugz
#
(cd /root && ln -s ../mnt/tb/sdata/.bugzrc) || exit 1
(cd /etc/ssmtp && ln -sf ../../mnt/tb/sdata/ssmtp.conf) || exit 1

exit 0

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


# MTA, bugz et. al
#
function RunSetupScript() {
  date
  echo " run setup script ..."
  cd ~tinderbox/

  nice -n 1 sudo ${0%/*}/chr.sh $mnt '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log'
  rc=$?

  if [[ $rc -ne 0 ]]; then
    date
    echo " setup was NOT successful (rc=$rc) @ $mnt"
    echo
    tail -v -n 1000 $mnt/var/tmp/tb/setup.sh.log
    echo
    exit $rc
  fi

  echo
}


function DryrunHelper() {
  date
  echo " dry run ..."
  tail -v -n 100 $mnt/etc/portage/make.conf.USE
  echo

  # check that the thrown USE flags do not yield into circular or other non-resolvable dependencies
  #
  nice -n 1 sudo ${0%/*}/chr.sh $mnt 'emerge --update --deep --changed-use --backtrack=30 --pretend @world &> /var/tmp/tb/dryrun.log'
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    grep -H -A 32 -e 'The following USE changes are necessary to proceed:'                \
                  -e 'One of the following packages is required to complete your request' \
                  $mnt/var/tmp/tb/dryrun.log && rc=12
  fi

  if [[ $rc -ne 0 ]]; then
    echo " ... was NOT successful (rc=$rc):"
    echo
    tail -v -n 1000 $mnt/var/tmp/tb/dryrun.log
    echo
  else
    echo " ... succeeded"
  fi

  return $rc
}


function Dryrun() {
  if [[ "$useflags" = "ThrowUseFlags" ]]; then
    i=0
    while :; do
      ((i=i+1))
      echo
      date
      echo "i=$i==========================================================="
      echo
      cat << EOF > $mnt/etc/portage/make.conf.USE
USE="
$(ThrowUseFlags)
"
EOF
      DryrunHelper && break

      # after a given amount of attempts hold for a while to hope that the portage tree will be healed ...
      #
      if [[ $(($i % 20)) = 0 ]]; then
        echo -e "\n\n TOO MUCH ATTEMPTS, WILL WAIT 1 HOUR ...\n\n"
        sleep 3600
      fi

    done
  else
    cat << EOF > $mnt/etc/portage/make.conf.USE
USE="
${useflags}
"
EOF

    DryrunHelper || exit $?
  fi

  echo
  date
  echo "  setup OK"
}


#############################################################################
#
# main
#
#############################################################################
export LANG=C

date
echo " $0 started"
echo
if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

if [[ $# -gt 0 ]]; then
  echo "   additional args are given: '${@}'"
  echo
fi

repo_gentoo=$(  portageq get_repo_path / gentoo)
repo_libressl=$(portageq get_repo_path / libressl)
repo_local=$(   portageq get_repo_path / local)
repo_musl=$(    portageq get_repo_path / musl)

tbdistdir=~tinderbox/distfiles
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s | xargs -n 1 | shuf | xargs)

SetOptions

while getopts a:f:k:l:m:o:p:t:u: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;
    f)  features="$OPTARG"
        ;;
    k)  keyword="$OPTARG"
        if [[ "$keyword" = "stable" ]]; then
          libressl="n"
          testfeature="n"
        fi
        ;;
    l)  libressl="$OPTARG"
        ;;
    m)  multilib="$OPTARG"
        ;;
    o)  # derive certain image configuration(s) from a given origin
        #
        origin="$OPTARG"
        if [[ ! -e $origin ]]; then
          echo " \$origin '$origin' doesn't exist"
          exit 1
        fi

        profile=$(cd $origin && readlink ./etc/portage/make.profile | sed -e 's,.*/profiles/,,' | cut -f4- -d'/' -s)
        if [[ -z "$profile" ]]; then
          echo " can't derive \$profile from '$origin'"
          exit 1
        fi

        useflags="$(cat $origin/etc/portage/make.conf.USE)"
        features="$(source $origin/etc/portage/make.conf && echo $FEATURES)"

        grep -q '^ACCEPT_KEYWORDS=.*~amd64' $origin/etc/portage/make.conf && keyword="unstable" || keyword="stable"
        grep -q 'ABI_X86="32 64"'           $origin/etc/portage/make.conf && multilib="y"       || multilib="n"
        grep -q 'FEATURES="test'            $origin/etc/portage/make.conf && testfeature="y"    || testfeature="n"
        [[ $origin =~ "libressl" ]] && libressl="y" || libressl="n"
        [[ $profile =~ "/musl" ]]   && musl="y"     || musl="n"

        ;;
    p)  profile=$OPTARG
        ;;
    t)  testfeature="$OPTARG"
        ;;
    u)  useflags="$(echo $OPTARG | PrintUseFlags)"
        ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

CheckOptions
ComputeImageName
CreateImageDir
UnpackStage3
CompileRepoFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklog
CreateSetupScript
RunSetupScript
Dryrun

cd ~tinderbox/run
ln -s ../$mnt

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "${0%/*}/start_img.sh $name"
fi

exit 0
