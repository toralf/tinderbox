#!/bin/sh
#
# set -x

# setup a new tinderbox image
#
# typical call:
#
# echo "cd ~/img2; sudo /opt/tb/bin/tbs.sh -p 17.0/desktop/gnome -l y -m n" | at now + 0 min

#############################################################################
#
# functions
#

# chooses *up to* n-1 arbitrarily choosen USE flags, about 1/m of them are masked
#
function ThrowUseFlags()  {
  n=50
  m=10

  grep -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' /usr/portage/profiles/use{,.local}.desc |\
  cut -f2 -d ':' |\
  cut -f1 -d ' ' |\
  egrep -v -e '32|64|^armv|bindist|build|cdinstall|gcj|hostname|kill|linguas|make-symlinks|minimal|multilib|musl|oci8|pax|qt4|tools|selinux|static|systemd|test|uclibc|vim-syntax' |\
  sort -u --random-sort |\
  head -n $(($RANDOM % $n)) |\
  sort |\
  while read flag
  do
    if [[ $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-$flag "
    else
      echo -n "$flag "
    fi
  done
}


# helper of main()
# set variables to arbitrarily choosen values
# might be overwritten by command line parameter
#
function SetOptions() {
  autostart="y"   # start the image after setup
  origin=""       # clone from the specified image

  # 17.0 rules nowadays
  #
  profile=$(eselect profile list | awk ' { print $2 } ' | grep -e "^default/linux/amd64/17.0" | cut -f4- -d'/' -s | grep -v -e '/x32' -e '/developer' -e '/selinux' | sort --random-sort | head -n 1)

  # stable
  #
  keyword="unstable"
  if [[ $(($RANDOM % 40)) -eq 0 ]]; then
    if [[ ! $profile =~ "17" ]]; then
      keyword="stable"
    fi
  fi

  # LibreSSL
  #
  libressl="n"
  if [[ $(($RANDOM % 3)) -eq 0 ]]; then
    libressl="y"
  fi

  # ABI_X86="32 64"
  #
  multilib="n"
  if [[ $(($RANDOM % 8)) -eq 0 ]]; then
    if [[ ! $profile =~ "no-multilib" ]]; then
      multilib="y"
    fi
  fi

  # FEATURES=test
  #
  testfeature="n"
  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    if [[ "$keyword" != "stable" ]]; then
      testfeature="y"
    fi
  fi

  useflags=$(ThrowUseFlags)
}


function CheckOptions() {
  if [[ ! -d /usr/portage/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: $profile"
    exit 2
  fi

  if [[ "$keyword" != "stable" && "$keyword" != "unstable" ]]; then
    echo " wrong value for \$keyword: $keyword"
    exit 2
  fi

  if [[ "$libressl" != "y" && "$libressl" != "n" ]]; then
    echo " wrong value for \$libressl: $libressl"
    exit 2
  fi

  if [[ "$multilib" != "y" && "$multilib" != "n" ]]; then
    echo " wrong value for \$multilib $multilib"
    exit 2
  fi

  if [[ "$testfeature" != "y" && "$testfeature" != "n" ]]; then
    echo " wrong value for \$testfeature $testfeature"
    exit 2
  fi
}


# helper of UnpackStage3()
# deduce the tinderbox image name
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

  name="$(echo $name | sed -e 's/_[-_]/_/g' -e 's/_$//')"
}


# download (if needed), verify and unpack the stage3 file
#
function UnpackStage3()  {
  latest=$distfiles/latest-stage3.txt
  wget --quiet $wgethost/$wgetpath/latest-stage3.txt --output-document=$latest || exit 3

  case $profile in
    17.0/hardened)
      stage3=$(grep "/hardened/stage3-amd64-hardened-20.*\.tar\." $latest)
      ;;

    17.0/no-multilib)
      stage3=$(grep "/stage3-amd64-nomultilib-20.*\.tar\." $latest)
      ;;

    17.0/no-multilib/hardened)
      stage3=$(grep "/hardened/stage3-amd64-hardened+nomultilib-20.*\.tar\." $latest)
      ;;

    *systemd*)
      stage3=$(grep "/systemd/stage3-amd64-systemd-20.*\.tar\." $latest)
      ;;

    *)
      stage3=$(grep "/stage3-amd64-20.*\.tar\." $latest)
      ;;
  esac

  stage3=$(echo $stage3 | cut -f1 -d' ' -s)
  if [[ -z "$stage3" ]]; then
    echo "can't get stage3 filename for profile '$profile'"
    exit 3
  fi

  f=$distfiles/$(basename $stage3)
  if [[ ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=$distfiles
    if [[ $? -ne 0 ]]; then
      echo "can't download stage3 files '$stage3' for profile '$profile'"
      exit 4
    fi
  fi

  # do this once before:
  #
  # gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys 0x9E6438C817072058
  # gpg --edit-key 0x9E6438C817072058
  # and set "trust" to 5 (==ultimately)
  #
  # maybe: do the same for 0xBB572E0E2D182910
  #
  gpg --quiet --verify $f.DIGESTS.asc || exit 4
  echo

  mkdir $name || exit 4
  cd $name    || exit 4
  tar -xpf $f --xattrs --exclude='./dev/*' || exit 4
}


# configure 3 repositories and prepare 1 additional (foo)
# the local repository must rule always
# the first 3 are synced outside of the image
# [foo] would be synced in job.sh as a daily task
#
function CompileRepoFiles()  {
  mkdir -p     ./etc/portage/repos.conf/
  cat << EOF > ./etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo
auto-sync = no

[gentoo]
priority = 1

[tinderbox]
priority = 2

#[foo]
#priority = 3

[local]
priority = 99
EOF

  cat << EOF > ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
EOF

  cat << EOF > ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location  = /tmp/tb/data/portage
masters   = gentoo
EOF

  cat << EOF > ./etc/portage/repos.conf/foo.conf
#[foo]
#location  = /usr/local/foo
#auto-sync = yes
#sync-type = git
#sync-uri  = https://anongit.gentoo.org/git/proj/foo.git
EOF

  cat << EOF > ./etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
EOF
}


# compile make.conf
#
function CompileMakeConf()  {
  sed -i  -e '/^CFLAGS="/d'       \
          -e '/^CXXFLAGS=/d'      \
          -e '/^CPU_FLAGS_X86=/d' \
          -e '/^USE=/d'           \
          -e '/^PORTDIR=/d'       \
          -e '/^PKGDIR=/d'        \
          -e '/^#/d'              \
          -e '/^DISTDIR=/d'       \
          ./etc/portage/make.conf

  # "tinderbox" user needs to be in group "portage" for this
  #
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf

  if [[ -e $origin/etc/portage/make.conf ]]; then
    l10n=$(grep "^L10N=" $origin/etc/portage/make.conf | cut -f2- -d'=' -s)
  else
    l10n="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  features="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox cgroup -news"

  cat << EOF >> ./etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native -Wall"
CXXFLAGS="-O2 -pipe -march=native"

USE="
$( echo $useflags | xargs -s 78 | sed 's/^/  /g' )

  ssp -bindist -cdinstall -oci8 -pax_kernel -valgrind
"
# legacy from hardened profile
#
PAX_MARKINGS="none"

ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '"~amd64"' || echo '"amd64"' )

FEATURES="$features"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build --with-bdeps=y --complete-graph=y --backtrack=500 --autounmask-keep-masks=y"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
ACCEPT_LICENSE="*"
CLEAN_DELAY=0

# see /etc/portage/package.env/noconcurrent and /etc/portage/package.env/noconcurrent
#
#MAKEOPTS="-j1"

L10N="$l10n"
VIDEO_CARDS=""

DISTDIR="$distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="http://mirror.netcologne.de/gentoo/ http://ftp.halifax.rwth-aachen.de/gentoo/ http://ftp.uni-erlangen.de/pub/mirrors/gentoo http://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/"

# https://bugs.gentoo.org/640930
#
FETCHCOMMAND="\${FETCHCOMMAND} --continue"

# https://bugs.gentoo.org/640290
#
PORTAGE_XATTR_EXCLUDE="${PORTAGE_XATTR_EXCLUDE} user.xdg.*"

EOF
}


# create portage directories
# symlink or copy /tmp/tb/data/** to the appropriate target dirs
#
function CompilePortageFiles()  {
  mkdir ./tmp/tb ./usr/portage ./var/tmp/distfiles ./var/tmp/portage 2>/dev/null

  for d in package.{accept_keywords,env,mask,unmask,use} env profile
  do
    [[ ! -d ./etc/portage/$d ]] && mkdir ./etc/portage/$d
    chmod 777 ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../tmp/tb/data/patches)

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    (cd ./etc/portage/$d && cp ../../../tmp/tb/data/$d.common common)
  done

  for d in package.{accept_keywords,unmask}
  do
    (cd ./etc/portage/$d && cp ../../../tmp/tb/data/$d.$keyword $keyword)
  done

  touch       ./etc/portage/package.mask/self     # contains failed package at this image
  chmod a+rw  ./etc/portage/package.mask/self

  touch      ./etc/portage/package.use/setup      # USE flags added at setup
  chmod a+rw ./etc/portage/package.use/setup

  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    (cd ./etc/portage/package.use && cp ../../../tmp/tb/data/package.use.ff-and-tb ff-and-tb)
  fi

  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    (cd ./etc/portage/package.use && cp ../../../tmp/tb/data/package.use.ffmpeg ffmpeg)
  fi

  echo "*/* $(cpuid2cpuflags)" > ./etc/portage/package.use/00cpuflags

  # force "test", useful if there's no system-wide "test"
  #
  echo 'FEATURES="test"'         > ./etc/portage/env/test

  # build w/o "test", useful if test phase is knwown to be br0ken or takes too long
  #
  echo 'FEATURES="-test"'         > ./etc/portage/env/notest

  # breakage is forced in job.sh by the XDG_* variables
  #
  echo 'FEATURES="-sandbox"'      > ./etc/portage/env/nosandbox

  # dito
  #
  echo 'FEATURES="-usersandbox"'  > ./etc/portage/env/nousersandbox

  # no parallel build
  #
  cat << EOF                      > ./etc/portage/env/noconcurrent
MAKEOPTS="-j1"
NINJAFLAGS="-j 1"
EGO_BUILD_FLAGS="-p 1"
GOMAXPROCS="1"
GO19CONCURRENTCOMPILATION=0
RUSTFLAGS="-C codegen-units=1"
EOF

  echo '*/* noconcurrent'         > ./etc/portage/package.env/noconcurrent
}


# configure DNS
# configure vim (eg.: avoid interactive question)
#
function CompileMiscFiles()  {
  # resolve hostname to "127.0.0.1" or "::1" respectively
  #
  cat <<EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  h=$(hostname)
  cat <<EOF > ./etc/hosts
127.0.0.1 localhost $h.localdomain $h
::1       localhost $h.localdomain $h
EOF

  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0
EOF
}


# update_backlog.sh writes into backlog.upd
# job,sh writes into backlog.1st
# the default backlog should not be written after setup
#
function CreateBacklog()  {
  backlog=./tmp/backlog

  truncate -s 0 $backlog{,.1st,.upd}
  chmod a+w $backlog{,.1st,.upd}

  qsearch --all --nocolor --name-only --quiet | sort --random-sort >> $backlog

  if [[ -e $origin ]]; then
    # no replay of @sets or %commands, just tasks
    # we intentionally don't want to replay `qlist -ICv`
    #
    echo "INFO finished replay of task history of $origin"    >> $backlog.1st
    grep -v -E "^(%|@)" $origin/tmp/task.history | tac | uniq >> $backlog.1st
    echo "INFO starting replay of task history of $origin"    >> $backlog.1st
  fi

  cat << EOF >> $backlog.1st
@world
@system
app-portage/eix
app-portage/pfl
%emerge -u sys-kernel/gentoo-sources
EOF

  if [[ "$libressl" = "y" ]]; then
    cat << EOF >> $backlog.1st
%emerge -C openssl
%emerge -f dev-libs/libressl net-misc/openssh mail-mta/ssmtp net-misc/wget dev-lang/python
EOF
    # quirks for an easier image setup
    #
    cat << EOF > /etc/portage/package.use/libressl
net-misc/iputils          libressl -gcrypt
sys-auth/polkit           -kde
EOF
    chmod a+rw /etc/portage/package.use/libressl

    cat << EOF >> /etc/portage/make.conf
CURL_SSL="libressl"
USE="\${USE} libressl -gnutls -openssl"
EOF
  fi

  # 13.0 -> 17.0 profile switch needs at least: emerge -p1 $(find /usr/ -type f -name '*.a')
  # fortunately GCC upgrade makes most of the work already
  #
  if [[ ! $profile =~ "hardened" ]]; then
    cat << EOF >> $backlog.1st
%emerge -1 sys-apps/texinfo
%emerge -1 sys-apps/portage
%emerge -1 net-libs/liblockfile
%emerge -1 sys-devel/flex
%emerge -1 sys-libs/binutils-libs
%emerge -1 sys-devel/binutils
EOF
  fi

  # update GCC asap after setup
  #
  cat << EOF >> $backlog.1st
%emerge -u sys-devel/gcc
sys-apps/sandbox
EOF

if [[ $profile =~ "systemd" ]]; then
  echo "%dbus-uuidgen --ensure=/etc/machine-id" >> $backlog.1st
fi

  # the timestamp of this file is used to schedule @system upgrade once a day
  #
  touch ./tmp/@system.history
}


# repos.d/* , make.conf and all the stuff
#
function ConfigureImage()  {
  mkdir -p                  ./usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > ./usr/local/portage/metadata/layout.conf
  echo 'local'            > ./usr/local/portage/profiles/repo_name
  chown -R portage:portage  ./usr/local/portage/
  chmod g+s                 ./usr/local/portage/

  CompileRepoFiles
  CompileMakeConf
  CompilePortageFiles
  CompileMiscFiles
  CreateBacklog
}


# - configure locale, timezone, MTA etc
# - install and configure tools used in job.sh:
#     <package>                   <command/s>
#     app-arch/sharutils          uudecode
#     app-portage/gentoolkit      equery eshowkw revdep-rebuild
#     app-portage/portage-utils   qatom qdepends qlop
#     www-client/pybugz           bugz
# - few attemps to auto-fix USE flags deps
#
function CreateSetupScript()  {
  dryrun="emerge --deep --update --changed-use @system --pretend"

  cat << EOF > tmp/setup.sh
#!/bin/sh
#
# set -x

cd /etc/portage
ln -snf ../../usr/portage/profiles/default/linux/amd64/$profile make.profile || exit 6
[[ ! -e make.profile ]] && exit 6

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen -j1 || exit 6
eselect locale set en_US.utf8 || exit 6
env-update
source /etc/profile

emerge mail-mta/ssmtp || exit 7
emerge mail-client/mailx || exit 7
# contains credentials
(cd /etc/ssmtp && ln -snf ../../tmp/tb/sdata/ssmtp.conf) || exit 7

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 8
# contains credentials
(cd /root && ln -snf ../tmp/tb/sdata/.bugzrc) || exit 8

if [[ "$multilib" = "y" ]]; then
  echo 'ABI_X86="32 64"' >> /etc/portage/make.conf
fi

if [[ "$testfeature" = "y" ]]; then
  sed -i -e 's/FEATURES="/FEATURES="test /g' /etc/portage/make.conf
fi

rc=9
for i in 1 2 3 4 5
do
  $dryrun &> /tmp/dryrun.log
  if [[ \$? -eq 0 ]]; then
    rc=0
    break
  fi

  if [[ \$i -eq 5 ]]; then
    break
  fi

  echo "#round \$i" >> /etc/portage/package.use/setup
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u >> /etc/portage/package.use/setup
  grep -A 1 'by applying the following change' /tmp/dryrun.log | grep '^- ' | cut -f2,5 -d' ' -s | sed -e 's/^/>=/' -e 's/)//' >> /etc/portage/package.use/setup
  grep -m 1 -A 1 'by applying any of the following changes' /tmp/dryrun.log | grep '^- ' | cut -f2,5 -d' ' -s | sed -e 's/^/>=/' -e 's/)//' >> /etc/portage/package.use/setup

  # remove "+"
  #
  sed -i -e 's/+//g' /etc/portage/package.use/setup

  # last round didn't brought up a change ?
  #
  tail -n 1 /etc/portage/package.use/setup | grep -q '#round'
  if [[ \$? -eq 0 ]]; then
    break
  fi
done

exit \$rc
EOF
}


# MTA, bugz et al are needed
#
function EmergeMandatoryPackages() {
  CreateSetupScript

  cd /home/tinderbox/

  $(dirname $0)/chr.sh $mnt '/bin/bash /tmp/setup.sh &> /tmp/setup.log'
  rc=$?

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $mnt"
    echo

    if [[ $rc -eq 9 ]]; then
      cat $mnt/tmp/dryrun.log
    else
      cat $mnt/tmp/setup.log
    fi

    echo
    echo "    view ~/$mnt/tmp/dryrun.log"
    echo "    vi ~/$mnt/etc/portage/make.conf"
    echo "    sudo $(dirname $0)/chr.sh $mnt ' $dryrun '"
    echo "    (cd ~/run && ln -s ../$mnt)"
    echo "    start_img.sh $name"
    echo

    exit $rc
  fi
}


#############################################################################
#
# main
#
#############################################################################
echo "$0 started with $# args: '${@}'"
echo

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

while :
do
  SetOptions
  while getopts a:f:k:l:m:o:p:t:u: opt
  do
    case $opt in
      a)  autostart="$OPTARG"
          ;;
      f)  features="$features $OPTARG"
          ;;
      k)  keyword="$OPTARG"
          ;;
      l)  libressl="$OPTARG"
          ;;
      m)  multilib="$OPTARG"
          ;;
      o)  # derive image properties from an older one
          #
          origin="$OPTARG"
          if [[ ! -e $origin ]]; then
            echo "\$origin '$origin' doesn't exist"
            exit 2
          fi

          profile=$(cd $origin && readlink ./etc/portage/make.profile | sed 's,.*/profiles/,,' | cut -f4- -d'/' -s)
          if [[ -z "$profile" ]]; then
            echo "can't derive \$profile from '$origin'"
            exit 2
          fi

          useflags="$(source $origin/etc/portage/make.conf && echo $USE)"
          features="$(source $origin/etc/portage/make.conf && echo $FEATURES)"

          grep -q '^CURL_SSL="libressl"' $origin/etc/portage/make.conf
          if [[ $? -eq 0 ]]; then
            libressl="y"
            useflags="$(echo $useflags | xargs -n 1 | grep -v -e 'openssl' -e 'libressl' -e 'gnutls' | xargs)"
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

      p)  profile="$(echo $OPTARG | sed -e 's,^/*,,' -e 's,/*$,,')"  # trim leading + trailing "/"
          ;;
      t)  testfeature="$OPTARG"
          ;;
      u)  # USE flags are
          # - defined in a statement like USE="..."
          # - or listed in a file
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
          exit 2
          ;;
    esac
  done
  CheckOptions

  ComputeImageName
  # test that there's no similar image in ~/run
  #
  ls -d /home/tinderbox/run/${name}_????????-?????? &>/dev/null
  if [[ $? -ne 0 ]]; then
    name="${name}_$(date +%Y%m%d-%H%M%S)"
    # relative path to the HOME dir
    #
    mnt=$(pwd | sed 's,/home/tinderbox/,,g')/$name
    break
  fi

done

echo " $mnt"
echo

# location of the stage3 file
#
distfiles=/var/tmp/distfiles

# the remote stage3 location
#
wgethost=http://mirror.netcologne.de/gentoo/
wgetpath=/releases/amd64/autobuilds

UnpackStage3            || exit 5
ConfigureImage          || exit 5
EmergeMandatoryPackages || exit 5

cd /home/tinderbox/run && ln -s ../$mnt || exit 11
echo " setup  OK: $name"

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
