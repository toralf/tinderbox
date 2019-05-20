#!/bin/bash
#
# set -x


# setup a new tinderbox image
# an exit code of 2 means to the caller: try it again
#
# typical call:
#
# echo "sudo /opt/tb/bin/setup_img.sh -t y -m n -l n -p 17.1/desktop -e y" | at now


#############################################################################
#
# functions
#

function ThrowUseFlags()  {
  # 1st: throw up to n-1 USE flags, up to m-1 of them are masked
  #      but exclude trouble makers et al.
  #
  n=40
  m=15

  grep -h -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' $repo_gentoo/profiles/use{,.local}.desc |\
  cut -f2 -d ':' | cut -f1 -d ' ' |\
  egrep -v -e '32|64|^armv|bindist|build|cdinstall|debug|forced-sandbox|gallium|gcj|ghcbootstrap|hostname|kill|libav|libressl|linguas|make-symlinks|minimal|monolithic|multilib|musl|nvidia|oci8|opencl|openssl|pax|prefix|tools|selinux|static|symlink|systemd|test|uclibc|vaapi|vdpau|vim-syntax|vulkan' |\
  sort -u | shuf -n $(($RANDOM % $n)) | sort |\
  while read flag
  do
    if [[ $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-"
    fi
    echo -n "$flag "
  done
}


# helper of main()
# will be overwritten by command line parameter if given
#
function SetOptions() {
  autostart="y"               # start the image after setup
  origin=""                   # derive settings from this image
  useflags=$(ThrowUseFlags)

  # throw a profile
  #
  profile=$(
    eselect profile list                                    |\
    awk ' { print $2 } '                                    |\
    grep -e "^default/linux/amd64/17.1"                     |\
    cut -f4- -d'/' -s                                       |\
    grep -v -e '/x32' -e '/musl' -e '/selinux' -e '/uclibc' |\
    shuf -n 1
  )

  # be more restrict wrt sandbox issues
  #
  features="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox cgroup -news protect-owned -collision-protect"

  # check only unstable amd64 per default
  #
  keyword="unstable"

  # alternative SSL vendor: LibreSSL
  #
  libressl="n"
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    libressl="y"
  fi

  # a "y" yields to ABI_X86="32 64" being set in make.conf
  #
  multilib="n"
  if [[ ! $profile =~ "no-multilib" ]]; then
    if [[ $(($RANDOM % 16)) -eq 0 ]]; then
      multilib="y"
    fi
  fi

  # optional: suffix of the image name
  #
  suffix=""

  # FEATURES=test
  #
  testfeature="n"
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    testfeature="y"
  fi
}


# helper of main()
#
function CheckOptions() {
  if [[ -z "$profile" || ! -d $repo_gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: $profile"
    exit 1
  fi

  if [[ "$keyword" != "stable" && "$keyword" != "unstable" ]]; then
    echo " wrong value for \$keyword: $keyword"
    exit 1
  fi

  if [[ "$libressl" != "y" && "$libressl" != "n" ]]; then
    echo " wrong value for \$libressl: $libressl"
    exit 1
  fi

  if [[ "$multilib" != "y" && "$multilib" != "n" ]]; then
    echo " wrong value for \$multilib: $multilib"
    exit 1
  fi

  if [[ "$testfeature" != "y" && "$testfeature" != "n" ]]; then
    echo " wrong value for \$testfeature: $testfeature"
    exit 1
  fi
}


# helper of UnpackStage3()
#
function ComputeImageName()  {
  name="$(echo $profile | tr '/' '-')_"

  if [[ "$keyword" = "stable" ]]; then
    name="$name-stable"
  fi

  if [[ "$libressl" = "y" ]]; then
    name="$name-libressl"
  fi

  if [[ "$multilib" = "y" ]]; then
    name="$name-abi32+64"
  fi

  if [[ "$testfeature" = "y" ]]; then
    name="$name-test"
  fi

  if [[ -n "$suffix" ]]; then
    name="$name-$suffix"
  fi

  name="$(echo $name | sed -e 's/_[-_]/_/g' -e 's/_$//')"
}


function CreateImageDir() {
  name="${name}_$(date +%Y%m%d-%H%M%S)"
  mkdir $name || exit 1

  # relative path to ~tinderbox
  #
  mnt=$(pwd | sed 's,/home/tinderbox/,,g')/$name

  echo
  echo " new image: $mnt"
  echo
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  # the remote stage3 location
  #
  wgeturl=http://ftp.halifax.rwth-aachen.de/gentoo/releases/amd64/autobuilds

  latest=$distdir/latest-stage3.txt
  wget --quiet $wgeturl/latest-stage3.txt --output-document=$latest || exit 1

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

    *)
      stage3=$(grep "/stage3-amd64-20.*\.tar\." $latest)
      ;;
  esac

  stage3=$(echo $stage3 | cut -f1 -d' ' -s)
  if [[ -z "$stage3" ]]; then
    echo "can't get stage3 filename for profile '$profile'"
    exit 1
  fi

  f=$distdir/$(basename $stage3)
  if [[ ! -s $f ]]; then
    date
    echo "downloading $stage3 ..."
    wget --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$distdir
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo " can't download stage3 file '$stage3', rc=$rc"
      rm -f $f{,.DIGESTS.asc}
      exit 1
    fi
  fi

  # do this once before:
  #
  # gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys <key>
  # gpg --edit-key <key>
  # and set "trust" to 5 (==ultimately)
  #
  echo
  date
  gpg --quiet --verify $f.DIGESTS.asc || exit 1
  echo

  date
  cd $name
  echo " untar'ing $f ..."
  tar -xf $f --xattrs --exclude='./dev/*' || exit 1
}


# configure remote (bind mounted, see chr.sh) and image specific repositories
#
function CompileRepoFiles()  {
  mkdir -p     ./etc/portage/repos.conf/

  cat << EOF > ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location = $repo_gentoo

EOF

  cat << EOF > ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location = /tmp/tb/data/portage

EOF

  # this is an image specific repository
  # nevertheless use the same location as at the host
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
priority = 30

[local]
priority = 99

EOF

  if [[ "$libressl" = "y" ]]; then
    mkdir -p ./$repo_libressl
    cat << EOF > ./etc/portage/repos.conf/libressl.conf
[libressl]
location = $repo_libressl

EOF

  cat << EOF >> ./etc/portage/repos.conf/default.conf
[libressl]
priority = 20

EOF

  fi
}


# compile make.conf
#
function CompileMakeConf()  {
  # strip away the following lines
  #
  sed -i  -e '/^CFLAGS="/d'       \
          -e '/^CXXFLAGS=/d'      \
          -e '/^CPU_FLAGS_X86=/d' \
          -e '/^USE=/d'           \
          -e '/^PORTDIR=/d'       \
          -e '/^PKGDIR=/d'        \
          -e '/^#/d'              \
          -e '/^DISTDIR=/d'       \
          ./etc/portage/make.conf

  # the "tinderbox" user have to be put in group "portage" to make this effective
  #
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf

  # throw up to 10 languages
  #
  if [[ -n "$origin" && -e $origin/etc/portage/make.conf ]]; then
    l10n=$(grep "^L10N=" $origin/etc/portage/make.conf | cut -f2- -d'=' -s | tr -d '"')
  else
    l10n="$(grep -v -e '^$' -e '^#' $repo_gentoo/profiles/desc/l10n.desc | cut -f1 -d' ' | shuf -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  cat << EOF > ./etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="\${CFLAGS}"

RUSTFLAGS="-C target-cpu=native -v -C codegen-units=1"

USE="
$(echo $useflags | xargs -s 78 | sed 's/^/  /g')

  ssp -cdinstall -oci8 -pax_kernel -valgrind -symlink
"

$([[ ! $profile =~ "hardened" ]] && echo 'PAX_MARKINGS="none"')
$([[ "$multilib" = "y" ]] && echo 'ABI_X86="32 64"')
ACCEPT_KEYWORDS=$([[ "$keyword" = "unstable" ]] && echo '"~amd64"' || echo '"amd64"')

# this is a tinderbox
ACCEPT_LICENSE="* -@EULA"

FEATURES="$features"
EMERGE_DEFAULT_OPTS="--with-bdeps=y --verbose-conflicts --nospinner --tree --quiet-build --autounmask-keep-masks=y --complete-graph=y --backtrack=500 --verbose --color=n --autounmask=n"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
CLEAN_DELAY=0

L10N="$l10n"
VIDEO_CARDS=""

DISTDIR="$distdir"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="http://ftp.halifax.rwth-aachen.de/gentoo/ http://gentoo.mirrors.ovh.net/gentoo-distfiles/ https://mirror.netcologne.de/gentoo/ http://ftp.fau.de/gentoo"

QEMU_SOFTMMU_TARGETS="x86_64 i386"
QEMU_USER_TARGETS="\$QEMU_SOFTMMU_TARGETS"

EOF
}


# create portage directories + files + symlinks from /tmp/tb/data/... to appropriate target(s)
#
function CompilePortageFiles()  {
  mkdir -p ./tmp/tb ./$repo_gentoo ./$distdir ./var/tmp/portage

  for d in package.{accept_keywords,env,mask,unmask,use} env
  do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir       ./etc/portage/$d
    fi
    chmod 777     ./etc/portage/$d
    chgrp portage ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../tmp/tb/data/patches)

  touch       ./etc/portage/package.mask/self     # contains failed packages of this image
  chmod a+rw  ./etc/portage/package.mask/self

  # useful if package specific test phase is known to be br0ken or takes too long
  #
  echo 'FEATURES="-test"'                         > ./etc/portage/env/notest

  # at the 2nd attempt to emerge of a package do still run the test phase (even it failed before)
  # to preserve the same dep tree - but do ignore the test phase result
  #
  #
  echo 'FEATURES="test-fail-continue"'            > ./etc/portage/env/test-fail-continue

  # re-try failing packages w/o sandbox'ing
  #
  echo 'FEATURES="-sandbox -usersandbox"'         > ./etc/portage/env/nosandbox

  # no parallel build
  #
  cat << EOF                                      > ./etc/portage/env/noconcurrent
MAKEOPTS="-j1"
NINJAFLAGS="-j1"
EGO_BUILD_FLAGS="-p 1"
GOMAXPROCS="1"
GO19CONCURRENTCOMPILATION=0
RUST_TEST_THREADS=1
RUST_TEST_TASKS=1
EOF

  echo '*/* noconcurrent'                         > ./etc/portage/package.env/00noconcurrent

  echo "*/* $(cpuid2cpuflags)"                    > ./etc/portage/package.use/00cpuflags

  if [[ $profile =~ '/systemd' ]]; then
    cp ~tinderbox/tb/data/package.env.00systemd     ./etc/portage/package.env/00systemd
    cp ~tinderbox/tb/data/package.use.00systemd     ./etc/portage/package.use/00systemd
  fi

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    cp ~tinderbox/tb/data/$d.00common               ./etc/portage/$d/00common
  done

  for d in package.{accept_keywords,unmask}
  do
    cp ~tinderbox/tb/data/$d.00$keyword             ./etc/portage/$d/00$keyword
  done

  if [[ "$testfeature" = "y" ]]; then
    cp ~tinderbox/tb/data/package.env.00notest      ./etc/portage/package.env/00notest
    cp ~tinderbox/tb/data/package.use.00test        ./etc/portage/package.use/00test
  else
    # squash any (unusual) attempt to run a test phase
    #
    echo "*/* notest"                             > ./etc/portage/package.env/00notest
  fi

  if [[ "$multilib" = "y" ]]; then
    cp ~tinderbox/tb/data/package.use.00abi32+64    ./etc/portage/package.use/00abi32+64
  fi

  touch ./tmp/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./tmp/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./tmp/task
}


function CompileMiscFiles()  {
  echo $name > ./tmp/name

  # use local (==host) DNS resolver
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

  # from leio
  # https://bugs.gentoo.org/667324
  #
  echo 'qlist -IC dev-util/glib-utils >/dev/null && emerge --unmerge dev-util/glib-utils' > ./tmp/pretask.sh
  chmod go-w ./tmp/pretask.sh
}


# /tmp/backlog.upd : update_backlog.sh writes to it
# /tmp/backlog     : filled by setup_img.sh
# /tmp/backlog.1st : filled by setup_img.sh, job.sh and retest.sh write to it
#
function CreateBacklog()  {
  bl=./tmp/backlog

  truncate -s 0           $bl{,.1st,.upd}
  chmod ug+w              $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}

  # sort is needed b/c more than one repository is configured
  #
  qsearch --all --nocolor --name-only --quiet | sort -u | shuf >> $bl

  if [[ -e $origin ]]; then
    # no replay of @sets or %commands
    # a replay of 'qlist -ICv' is intentionally not wanted
    #
    echo "INFO finished replay of task history of $origin"    >> $bl.1st
    grep -v -E "^(%|@)" $origin/tmp/task.history | uniq | tac >> $bl.1st
    echo "INFO starting replay of task history of $origin"    >> $bl.1st
  fi

  # update @system and @world before working on packages
  # this is the last time where depclean is run w/o "-p" (and have to work)
  #
  cat << EOF >> $bl.1st
%emerge --depclean
@world
@system
EOF

  # asturm: give media-libs/jpeg a chance
  #
  # but there's a poppler issue: https://bugs.gentoo.org/670252
  #
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    echo "media-libs/jpeg" >> $bl.1st
  fi

  # whissi: https://bugs.gentoo.org/669216
  # this is a mysql alternative engine, emerge it before @system or @world pulls the default (mysqld)
  #
  if [[ "$libressl" = "y" ]]; then
    if [[ $(($RANDOM % 16)) -eq 0 ]]; then
      echo "dev-db/percona-server" >> $bl.1st
    fi
  fi

  # upgrade portage itself before @system or @world
  #
  echo "sys-apps/portage" >> $bl.1st

  # switch to LibreSSL soon
  #
  if [[ "$libressl" = "y" ]]; then
    # fetch all mandatory packages which must either be (re-)build or have to act as a fallback
    # wget is crucial b/c it is used by portage to fetch sources
    #
    # @preserved-rebuild will be added to backlog.1st by job.sh
    # caused by the log message of the unmerge operation of openssl
    # therefore "%emerge @preserved-rebuild" should never fail eventually
    #
    cat << EOF >> $bl.1st
%emerge @preserved-rebuild
%emerge --unmerge openssl
%emerge -f dev-libs/openssl dev-libs/libressl net-misc/openssh net-misc/wget dev-lang/python
%cp /tmp/tb/data/package.use.00libressl /etc/portage/package.use/
EOF
  fi

  # at least systemd and virtualbox need (compiled) kernel sources and would fail in @preserved-rebuild otherwise
  # use "%..." b/c IGNORE_PACKAGES contains sys-kernel/*
  #
  if [[ $(($RANDOM % 2)) -eq 0 || $keyword = "stable" ]]; then
    echo "%emerge -u sys-kernel/gentoo-sources"   >> $bl.1st
  else
    echo "%emerge -u sys-kernel/vanilla-sources"  >> $bl.1st
  fi

  switch_profile="n"
  readlink ./etc/portage/make.profile | grep -q "/17.0"
  if [[ $? -eq 0 ]]; then
    switch_profile="y"
  fi

  if [[ "$switch_profile" = "y" ]]; then
    if [[ ! $profile =~ "no-multilib" ]]; then
      echo "%emerge -1 /lib32 /usr/lib32" >> $bl.1st
    fi
  fi

  # upgrade GCC asap
  #
  if [[ $keyword = "unstable" ]]; then
    #   %...      : bail out if it fails
    #   no --deep : that would result effectively in @system
    #   =         : do not upgrade the current (slotted) version
    # dev-libs/...: avoid a forced rebuild of GCC in @system
    #
    echo "%emerge -u =$(ACCEPT_KEYWORDS="~amd64" portageq best_visible / sys-devel/gcc) dev-libs/mpc dev-libs/mpfr" >> $bl.1st
  else
    echo "sys-devel/gcc" >> $bl.1st
  fi

  # switch to 17.1 profile
  #
  if [[ "$switch_profile" = "y" ]]; then
    cat << EOF >> $bl.1st
%eselect profile set --force default/linux/amd64/${profile}
%unsymlink-lib --finish
%source /etc/profile
%env-update
%unsymlink-lib --migrate
%unsymlink-lib --analyze
%emerge app-portage/unsymlink-lib
EOF
  fi

  # the stage4 of a systemd image would have this already done
  #
  if [[ $profile =~ "systemd" ]]; then
    echo "%systemd-machine-id-setup" >> $bl.1st
  fi

  # needed if Python is updated (eg. as dep of a newer portage during setup)
  # otherwise this is a no-op
  #
  echo "%eselect python update" >> $bl.1st
}


# - configure locale, timezone etc.
# - install and configure tools called in job.sh:
#     <package>                   <command/s>
#     mail-*                      MTA + mailx
#     app-arch/sharutils          uudecode
#     app-portage/gentoolkit      equery eshowkw revdep-rebuild
#     app-portage/portage-utils   qatom qdepends qlop
#     www-client/pybugz           bugz
# - dry run of @system
#
function CreateSetupScript()  {
  cat << EOF > ./tmp/setup.sh || exit 1
#!/bin/sh
#
# set -x

# the 17.x quirk will be removed soon
#
eselect profile set --force default/linux/amd64/$(echo $profile | sed -e 's/17.1/17.0/') || exit 1

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data || exit 1

echo "
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen -j1 || exit 1
eselect locale set en_US.UTF-8 || exit 1

if [[ $profile =~ "systemd" ]]; then
  echo 'LANG="en_US.UTF-8"' > /etc/locale.conf
fi

env-update
source /etc/profile

useradd -u $(id -u tinderbox) tinderbox

# separate steps to avoid that mailx implicitely pulls another MTA than ssmtp
#
emerge mail-mta/ssmtp     || exit 1
emerge mail-client/mailx  || exit 1

# contains credentials for mail-mta/ssmtp
#
(cd /etc/ssmtp && ln -sf ../../tmp/tb/sdata/ssmtp.conf) || exit 1

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 1

# contains credentials for www-client/pybugz
#
(cd /root && ln -s ../tmp/tb/sdata/.bugzrc) || exit 1

if [[ "$testfeature" = "y" ]]; then
  sed -i -e 's/FEATURES="/FEATURES="test /g' /etc/portage/make.conf
fi

# the very first @system must succeed
#
$dryrun &> /tmp/dryrun.log || exit 2
grep -A 32 'The following USE changes are necessary to proceed:' /tmp/dryrun.log && exit 2

exit 0

EOF

  chmod u+x ./tmp/setup.sh
}


# MTA, bugz et. al
#
function EmergeMandatoryPackages() {
  date
  echo " install mandatory packages ..."
  cd ~tinderbox/

  $(dirname $0)/chr.sh $mnt '/tmp/setup.sh &> /tmp/setup.sh.log'
  rc=$?

  echo
  if [[ $rc -ne 0 ]]; then
    echo " setup NOT successful (rc=$rc) @ $mnt"
    echo

    if [[ $rc -eq 2 ]]; then
      cat $mnt/tmp/dryrun.log
    else
      cat $mnt/tmp/setup.sh.log
    fi

    echo "
      view $mnt/tmp/dryrun.log
      echo '' >> $mnt/etc/portage/package.use/setup

      sudo $(dirname $0)/chr.sh $mnt ' $dryrun '

      (cd ~tinderbox/run && ln -s ../$mnt)
      start_img.sh $name

"
    exit $rc

  else
    echo " setup OK"
  fi
}


#############################################################################
#
# main
#
#############################################################################
date
echo " $0 started"
echo
if [[ $# -gt 0 ]]; then
  echo "   additional args are given: '${@}'"
  echo
fi

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

cd $(readlink ~tinderbox/img) || exit 1

repo_gentoo=$(  portageq get_repo_path / gentoo)
repo_libressl=$(portageq get_repo_path / libressl)
repo_local=$(   portageq get_repo_path / local)
distdir=$(      portageq distdir)

SetOptions

while getopts a:f:k:l:m:o:p:s:t:u: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;
    f)  features="$OPTARG"
        ;;
    k)  keyword="$OPTARG"
        ;;
    l)  libressl="$OPTARG"
        ;;
    m)  multilib="$OPTARG"
        ;;
    o)  # derive certian image configuration(s) from another one
        #
        origin="$OPTARG"
        if [[ ! -e $origin ]]; then
          echo " \$origin '$origin' doesn't exist"
          exit 1
        fi

        profile=$(cd $origin && readlink ./etc/portage/make.profile | sed -e 's,.*/profiles/,,' -e 's/17.0/17.1/' | cut -f4- -d'/' -s)
        if [[ -z "$profile" ]]; then
          echo " can't derive \$profile from '$origin'"
          exit 1
        fi

        useflags="$(source $origin/etc/portage/make.conf && echo $USE)"
        features="$(source $origin/etc/portage/make.conf && echo $FEATURES)"

        if [[ $origin =~ "libressl" ]]; then
          libressl="y"
        else
          libressl="n"
        fi

        grep -q '^ACCEPT_KEYWORDS=.*~amd64' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          keyword="unstable"
        else
          keyword="stable"
        fi

        grep -q 'ABI_X86="32 64"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          multilib="y"
        else
          multilib="n"
        fi
        ;;
    p)  profile=$OPTARG
        ;;
    s)  suffix="$OPTARG"
        ;;
    t)  testfeature="$OPTARG"
        ;;
    u)  # USE flags are either
        # - defined in a file as USE="..."
        # - or listed in a plain file
        # - or given at the command line
        #
        # "x" is a place holder for an empty USE flag set
        #
        if [[ -f "$OPTARG" ]] ; then
          useflags="$(source $OPTARG; echo $USE)"
          if [[ -z "$useflags" ]]; then
            useflags="$(cat $OPTARG)"
          fi
        elif [[ "$OPTARG" -eq "x" ]]; then
          useflags=""
        else
          useflags="$OPTARG"
        fi
        ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

dryrun="emerge --update --newuse --changed-use --changed-deps=y --deep @system --pretend"

CheckOptions
ComputeImageName

if [[ -z "$origin" ]]; then
  ls -d ~tinderbox/run/${name}_20??????-?????? 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "^^^ name=$name is already running"
    exit 2
  fi
fi

CreateImageDir
UnpackStage3
CompileRepoFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklog
CreateSetupScript
EmergeMandatoryPackages

cd ~tinderbox/run || exit 1
ln -s ../$mnt     || exit 1

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
