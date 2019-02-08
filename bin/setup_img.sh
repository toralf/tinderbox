#!/bin/bash
#
# set -x

# setup a new tinderbox image
#
# typical call:
#
# echo "cd ~/img && while :; do sudo /opt/tb/bin/setup_img.sh && break; done" | at now

# an exit code of 1 is an unrecoverable error, 2 means try it again

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

  tmp=/tmp/useflags

  grep -h -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' $repo_gentoo/profiles/use{,.local}.desc |\
  cut -f2 -d ':' |\
  cut -f1 -d ' ' |\
  tee $tmp  |\
  egrep -v -e '32|64|^armv|bindist|build|cdinstall|debug|gallium|gcj|ghcbootstrap|hostname|kill|libav|libressl|linguas|make-symlinks|minimal|monolithic|multilib|musl|nvidia|oci8|opencl|openssl|pax|prefix|tools|selinux|static|symlink|^system-|systemd|test|uclibc|vaapi|vdpau|vim-syntax|vulkan' |\
  sort -u --random-sort |\
  head -n $(($RANDOM % $n)) |\
  sort |\
  while read flag
  do
    if [[ $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-"
    fi
    echo -n "$flag "
  done

  # 2nd: prefer system libs over bundled ones
  #
  grep '^system-' $tmp |\
  while read flag
  do
    if [[ $(($RANDOM % 4)) -eq 0 ]]; then
      echo -n "$flag "
    fi
  done

  rm $tmp
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
    grep -e "^default/linux/amd64/17.0"                     |\
    cut -f4- -d'/' -s                                       |\
    grep -v -e '/x32' -e '/musl' -e '/selinux' -e '/uclibc' |\
    sort --random-sort                                      |\
    head -n 1
  )

  # switch to 17.1 profile
  #
  expprofile="n"
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    expprofile="y"
  fi

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
    if [[ $(($RANDOM % 10)) -eq 0 ]]; then
      multilib="y"
    fi
  fi

  # optional: suffix of the image name
  #
  suffix=""

  # FEATURES=test
  #
  testfeature="n"
  if [[ $(($RANDOM % 27)) -eq 0 ]]; then
    testfeature="y"
  fi
}


# helper of main()
#
function CheckOptions() {
  if [[ ! -d $repo_gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: $profile in $repo_gentoo"
    exit 1
  fi

  if [[ "$expprofile" != "y" && "$expprofile" != "n" ]]; then
    echo " wrong value for \$expprofile: $expprofile"
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
  if [[ "$expprofile" = "y" ]]; then
    name=$( echo $name | sed -e 's/17.0/17.1/g' )
  fi

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


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  latest=$distfiles/latest-stage3.txt
  wget --quiet $wgethost/$wgetpath/latest-stage3.txt --output-document=$latest || exit 1

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

    */systemd*)
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

  f=$distfiles/$(basename $stage3)
  if [[ ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=$distfiles
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo " can't download stage3 file '$stage3' of profile '$profile', rc=$rc"
      rm -f $f{,.DIGESTS.asc}
      exit 1
    fi
  fi

  # do this once before:
  #
  # gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys 0x9E6438C817072058
  # gpg --edit-key 0x9E6438C817072058
  # and set "trust" to 5 (==ultimately)
  #
  # do the same for 0xBB572E0E2D182910
  #
  gpg --quiet --verify $f.DIGESTS.asc || exit 1
  echo

  cd $name || exit 1
  echo " untar'ing $f ..."
  tar -xf $f --xattrs --exclude='./dev/*' || exit 1
}


# define and configure repositories
#
function CompileRepoFiles()  {
  mkdir -p      ./etc/portage/repos.conf/

  cat << EOF >> ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location = $repo_gentoo

sync-type = git
sync-uri = https://github.com/gentoo-mirror/gentoo.git
sync-depth = 1
sync-git-clone-extra-opts = -b master
#sync-git-verify-commit-signature = true

EOF

  cat << EOF >> ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location = /tmp/tb/data/portage

EOF

  mkdir -p                  ./$repo_local/{metadata,profiles}
  echo 'masters = gentoo' > ./$repo_local/metadata/layout.conf
  echo 'local'            > ./$repo_local/profiles/repo_name

  # this is image specific, not bind-mounted from the host
  # nevertheless use the same location
  #
  cat << EOF >> ./etc/portage/repos.conf/local.conf
[local]
location = $repo_local

EOF

  cat << EOF >> ./etc/portage/repos.conf/default.conf
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
    cat << EOF >> ./etc/portage/repos.conf/libressl.conf
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
    l10n="$(grep -v -e '^$' -e '^#' $repo_gentoo/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  cat << EOF >> ./etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="\${CFLAGS}"

USE="
$( echo $useflags | xargs --no-run-if-empty -s 78 | sed 's/^/  /g' )

  ssp -cdinstall -oci8 -pax_kernel -valgrind -symlink
"

$( [[ ! $profile =~ "hardened" ]] && echo 'PAX_MARKINGS="none"' )
$( [[ "$multilib" = "y" ]] && echo 'ABI_X86="32 64"' )
ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '"~amd64"' || echo '"amd64"' )

FEATURES="$features"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build --with-bdeps=y --complete-graph=y --backtrack=500 --autounmask-keep-masks=y"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
ACCEPT_LICENSE="@FREE"
CLEAN_DELAY=0

L10N="$l10n"
VIDEO_CARDS=""

DISTDIR="$distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
# this variable is used in job.sh to derive the image name
#
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="http://ftp.halifax.rwth-aachen.de/gentoo/ http://gentoo.mirrors.ovh.net/gentoo-distfiles/ https://mirror.netcologne.de/gentoo/ http://ftp.fau.de/gentoo"

QEMU_SOFTMMU_TARGETS="x86_64 i386"
QEMU_USER_TARGETS="\$QEMU_SOFTMMU_TARGETS"

EOF
}


# create portage directories and symlink /tmp/tb/data/<files> to the appropriate target dirs
#
function CompilePortageFiles()  {
  mkdir -p ./tmp/tb ./$repo_gentoo ./$distfiles ./var/tmp/portage 2>/dev/null

  for d in package.{accept_keywords,env,mask,unmask,use} env
  do
    [[ ! -d ./etc/portage/$d ]] && mkdir ./etc/portage/$d
    chmod 777 ./etc/portage/$d
    chgrp portage ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../tmp/tb/data/patches)

  touch       ./etc/portage/package.mask/self     # contains failed package at this image
  chmod a+rw  ./etc/portage/package.mask/self

  echo "*/* $(cpuid2cpuflags)"    > ./etc/portage/package.use/00cpuflags

  # build w/o "test", useful if package specific test phase is known to be br0ken or takes too long
  #
  echo 'FEATURES="-test"'         > ./etc/portage/env/notest

  # at 2nd attempt to emerge a package do ignore the test phase result
  # but do still run the test phase (even it will fail) to have the same dep tree
  #
  echo 'FEATURES="test-fail-continue"'  > ./etc/portage/env/test-fail-continue

  # certain types of sandbox issues are forced by the XDG_* settings in job.sh
  # at 2nd attempt retry affected packages w/o sandbox'ing
  #
  echo 'FEATURES="-sandbox"'      > ./etc/portage/env/nosandbox
  echo 'FEATURES="-usersandbox"'  > ./etc/portage/env/nousersandbox

  # no parallel build
  #
  cat << EOF                      > ./etc/portage/env/noconcurrent
MAKEOPTS="-j1"
NINJAFLAGS="-j1"
EGO_BUILD_FLAGS="-p 1"
GOMAXPROCS="1"
GO19CONCURRENTCOMPILATION=0
RUSTFLAGS="-C codegen-units=1"
RUST_TEST_THREADS=1
RUST_TEST_TASKS=1
EOF

  echo '*/* noconcurrent'           >> ./etc/portage/package.env/noconcurrent

  if [[ "$libressl" = "y" ]]; then
    # will be moved to its final destination after GCC update
    #
    cat << EOF > ./tmp/00libressl
*/*               libressl -gnutls -openssl
net-misc/curl     curl_ssl_libressl -curl_ssl_gnutls -curl_ssl_openssl

EOF
    echo 'dev-lang/python -bluetooth' >> ./etc/portage/package.use/python
  fi

  if [[ ! "$profile" =~ '/desktop/' ]]; then
    # would pull in X otherwise in a non-desktop profile
    #
    echo 'media-fonts/encodings -X' >> ./etc/portage/package.use/encodings
  fi

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    cp  ~tinderbox/tb/data/$d.common                ./etc/portage/$d/common
  done

  for d in package.{accept_keywords,unmask}
  do
    cp  ~tinderbox/tb/data/$d.$keyword              ./etc/portage/$d/$keyword
  done

  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    cp  ~tinderbox/tb/data/package.use.ff-and-tb    ./etc/portage/package.use/ff-and-tb
  fi

  if [[ $(($RANDOM % 8)) -eq 0 ]]; then
    cp  ~tinderbox/tb/data/package.use.ffmpeg       ./etc/portage/package.use/ffmpeg
  fi

  if [[ "$testfeature" = "y" ]]; then
    cp  ~tinderbox/tb/data/package.use.00test       ./etc/portage/package.use/00test
    cp  ~tinderbox/tb/data/package.env.notest       ./etc/portage/package.env/notest
  else
    echo "*/* notest"                             > ./etc/portage/package.env/notest
  fi

  if [[ "$multilib" = "y" ]]; then
    cp  ~tinderbox/tb/data/package.use.abi32+64     ./etc/portage/package.use/abi32+64
  fi

  touch ./tmp/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./tmp/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./tmp/task
}


function CompileMiscFiles()  {
  # use local DNS resolver
  #
  cat <<EOF >> ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  h=$(hostname)
  cat <<EOF >> ./etc/hosts
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
  chmod a+x ./tmp/pretask.sh
}


# /tmp/backlog.upd : update_backlog.sh writes to it
# /tmp/backlog     : filled by setup_img.sh
# /tmp/backlog.1st : filled by setup_img.sh, job.sh and retest.sh write to it
#
function CreateBacklog()  {
  bl=./tmp/backlog

  truncate -s 0 $bl{,.1st,.upd}            || exit 1
  chmod ug+w    $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}

  # all packages in a randomized order
  #
  qsearch --all --nocolor --name-only --quiet | sort --random-sort >> $bl

  if [[ -e $origin ]]; then
    # no replay of @sets or %commands
    # the replay of 'qlist -ICv' is intentionally not wanted
    #
    echo "INFO finished replay of task history of $origin"    >> $bl.1st
    grep -v -E "^(%|@)" $origin/tmp/task.history | uniq | tac >> $bl.1st
    echo "INFO starting replay of task history of $origin"    >> $bl.1st
  fi

  # update @system and @world before working on package lists
  #
  cat << EOF >> $bl.1st
@world
@system
EOF

  # asturm: give media-libs/jpeg a chance
  #
  # but there's a poppler issue: https://bugs.gentoo.org/670252
  #
  if [[ $(($RANDOM % 6)) -eq 0 ]]; then
    echo "media-libs/jpeg" >> $bl.1st
  fi

  # whissi: https://bugs.gentoo.org/669216
  # this is a mysql alternative engine, emerge it before @system or @world pulls the default (mysqld)
  #
  if [[ "$libressl" = "y" ]]; then
    if [[ $(($RANDOM % 8)) -eq 0 ]]; then
      echo "dev-db/percona-server" >> $bl.1st
    fi
  fi

  # upgrade portage before @system or @world
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
%mv /tmp/00libressl /etc/portage/package.use/
EOF
  fi

  # at least systemd and virtualbox need kernel sources and would fail in @preserved-rebuild otherwise
  #
  # use % here b/c IGNORE_PACKAGES contains sys-kernel/*
  #
  echo "%emerge -u sys-kernel/vanilla-sources" >> $bl.1st

  if [[ "$expprofile" = "y" ]]; then
    if [[ ! $profile =~ "no-multilib" ]]; then
      echo "%emerge -1 /lib32 /usr/lib32" >> $bl.1st
    fi
  fi

  # upgrade GCC asap
  #   %...      : bail out if it fails
  #   no --deep : that would result effectively in @system
  #   =         : do not upgrade the current (slotted) version
  # dev-libs/*  : avoid a forced rebuild of GCC in @system
  #
  echo "%emerge -u =$( ACCEPT_KEYWORDS="~amd64" portageq best_visible / sys-devel/gcc ) dev-libs/mpc dev-libs/mpfr" >> $bl.1st

  if [[ "$expprofile" = "y" ]]; then
    cat << EOF >> $bl.1st
%eselect profile set --force default/linux/amd64/$( echo $profile | sed 's/17.0/17.1/g' )
%unsymlink-lib --finish
%source /etc/profile
%env-update
%unsymlink-lib --migrate
%unsymlink-lib --analyze
%emerge app-portage/unsymlink-lib
EOF
  fi


  # the stage4 of a systemd ISO image ran it already
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
# - install and configure tools used in job.sh:
#     <package>                   <command/s>
#     mail-*                      MTA + mailx
#     app-arch/sharutils          uudecode
#     app-portage/gentoolkit      equery eshowkw revdep-rebuild
#     app-portage/portage-utils   qatom qdepends qlop
#     www-client/pybugz           bugz
# - dry run of @system
#
function CreateSetupScript()  {
  cat << EOF >> ./tmp/setup.sh || exit 1
#!/bin/sh
#
# set -x

# eselect sometimes can't be used for new unstable profiles
#
cd /etc/portage
ln -snf ../../$repo_gentoo/profiles/default/linux/amd64/$profile make.profile || exit 1

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

# needed at least in job.sh
#
useradd -u $(id -u tinderbox) tinderbox

emerge mail-mta/ssmtp || exit 1
emerge mail-client/mailx || exit 1

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
$dryrun &> /tmp/dryrun.log
if [[ \$? -ne 0 ]]; then
  exit 2
fi

exit 0

EOF
}


# MTA, bugz et. al
#
function EmergeMandatoryPackages() {
  cd  ~tinderbox/

  echo " install mandatory packages ..."

  $(dirname $0)/chr.sh $mnt '/bin/bash /tmp/setup.sh &> /tmp/setup.sh.log'
  rc=$?

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $mnt"
    echo

    if [[ $rc -eq 2 ]]; then
      cat $mnt/tmp/dryrun.log
    else
      cat $mnt/tmp/setup.sh.log
    fi

    # create commands, easy to copy+paste for ceonvenience
    #
    echo "
      view $mnt/tmp/dryrun.log
      echo '' >> $mnt/etc/portage/package.use/setup

      sudo $(dirname $0)/chr.sh $mnt ' $dryrun '

      (cd ~tinderbox/run && ln -s ../$mnt)
      start_img.sh $name

"

    exit $rc
  fi
}


#############################################################################
#
# main
#
#############################################################################
echo " $0 started"
echo
if [[ $# -gt 0 ]]; then
  echo "   additional args are given: '${@}'"
fi

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

cd $( readlink ~tinderbox/img ) || exit 1

repo_gentoo=$(   portageq get_repo_path / gentoo )
repo_libressl=$( portageq get_repo_path / libressl )
repo_local=$(    portageq get_repo_path / local )
distfiles=$(     portageq distdir )

SetOptions

while getopts a:e:f:k:l:m:o:p:s:t:u: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;
    e)  expprofile="$OPTARG"
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

        profile=$(cd $origin && readlink ./etc/portage/make.profile | sed 's,.*/profiles/,,' | cut -f4- -d'/' -s)
        if [[ -z "$profile" ]]; then
          echo " can't derive \$profile from '$origin'"
          exit 1
        fi

        useflags="$(source $origin/etc/portage/make.conf && echo $USE)"
        features="$(source $origin/etc/portage/make.conf && echo $FEATURES)"

        if [[ -f $origin/etc/portage/package.use/00libressl ]]; then
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
        fi
        ;;
    p)  profile="$(echo $OPTARG | cut -f4- -d'/' -s)" # OPTARG is eg.: default/linux/amd64/17.0/desktop/gnome
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
        if [[ -f "$OPTARG" ]] ; then
          useflags="$(source $OPTARG; echo $USE)"
          if [[ -z "$useflags" ]]; then
            useflags="$(cat $OPTARG)"
          fi
        else
          useflags="$OPTARG"
        fi
        ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

CheckOptions
ComputeImageName

ls -d ~tinderbox/run/${name}_20??????-?????? 2>/dev/null
if [[ $? -eq 0 ]]; then
  echo "name=$name is already running"
  exit 2
fi

# append the timestamp onto the image name
#
name="${name}_$(date +%Y%m%d-%H%M%S)"
mkdir $name || exit 1

# relative path to ~tinderbox
#
mnt=$(pwd | sed 's,/home/tinderbox/,,g')/$name

echo " $mnt"
echo

# the remote stage3 location
#
wgethost=http://ftp.halifax.rwth-aachen.de/gentoo/
wgetpath=/releases/amd64/autobuilds

UnpackStage3
CompileRepoFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklog

dryrun="emerge --update --newuse --changed-use --changed-deps=y --deep @system --pretend"
CreateSetupScript
EmergeMandatoryPackages

cd  ~tinderbox/run && ln -s ../$mnt || exit 1

echo
echo " setup OK"

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
