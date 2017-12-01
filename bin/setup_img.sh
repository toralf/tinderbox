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

function ThrowUseFlags()  {
  # grab up to n-1 USE flags, mask about 1/m of them
  #
  n=75
  m=10

  (
    grep -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' /usr/portage/profiles/use.desc
    grep -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' /usr/portage/profiles/use.local.desc | cut -f2 -d ':' -s
  ) |\
  cut -f1 -d ' ' |\
  grep -v   -e '32' -e '64' -e "^armv" -e 'bindist' -e 'build' -e 'cdinstall' \
            -e 'gcj' -e 'hostname' -e 'kill' -e 'linguas' -e 'make-symlinks' -e 'minimal' -e 'multilib' -e 'musl'  \
            -e 'oci8' -e 'pax' -e 'pic' -e 'qt4' -e 'tools' -e 'selinux' -e 'ssl' -e 'ssp' -e 'static' -e 'systemd'    \
            -e 'test' -e 'tls' -e 'uclibc' -e 'valgrind' -e 'vim-syntax' |\
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
}


# helper of main()
#
function SetOptions() {
  # choose an arbitrary profile
  # switch to 17.0 profile at every 2nd image
  #
  profile=$(eselect profile list | awk ' { print $2 } ' | grep -e "^default/linux/amd64/17.0" | cut -f4- -d'/' -s | grep -v -e '/x32' -e '/developer' -e '/selinux' | sort --random-sort | head -n 1)

  # stable
  #
  keyword="unstable"
  if [[ $(($RANDOM % 40)) -eq 0 ]]; then
    if [[ ! "$profile" =~ "17" ]]; then
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
    if [[ ! "$profile" =~ "no-multilib" ]]; then
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

  while getopts a:f:k:l:m:o:p:s:t:u: opt
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
      s)  stage3="$OPTARG"
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

  if [[ ! -d /usr/portage/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: $profile"
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

  duplicate=0
  ls -d /home/tinderbox/run/${name}_????????-?????? &>/dev/null
  if [[ $? -eq 0 ]]; then
    duplicate=1
  fi

  name="${name}_$(date +%Y%m%d-%H%M%S)"

  mnt=$(echo $image_dir | sed 's,/home/tinderbox/,,g')/$name
  echo " $mnt"
  echo

  return $duplicate
}


# download (if needed), verify and unpack the stage3 file
#
function UnpackStage3()  {
  if [[ -z "$stage3" ]]; then
    # latest file contains all relevant data
    #
    latest=$distfiles/latest-stage3.txt
    wget --quiet $wgethost/$wgetpath/latest-stage3.txt --output-document=$latest || exit 3

    b="$(basename $profile)"
    case $b in
      no-multilib)  stage3=$(grep "^20....../stage3-amd64-nomultilib-20.......tar.bz2" $latest | cut -f1 -d' ' -s)
      ;;
      systemd)      stage3=$(grep "^20....../$b/stage3-amd64-$b-20.......tar.bz2" $latest | cut -f1 -d' ' -s)
      ;;
      *)            stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $latest | cut -f1 -d' ' -s)
      ;;
    esac

    if [[ -z "$stage3" ]]; then
      echo "can't get stage 3 from profile '$profile'"
      exit 3
    fi
  fi

  f=$distfiles/$(basename $stage3)

  if [[ ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=$distfiles || exit 4
  fi

  # do this once before:
  #
  # gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys 0x9E6438C817072058
  # gpg --edit-key 0x9E6438C817072058
  #   and "trust" it (5==ultimately)
  # maybe: do the same for 0xBB572E0E2D182910
  #
  gpg --quiet --verify $f.DIGESTS.asc || exit 4
  echo

  mkdir $name || exit 4
  cd $name    || exit 4
  tar -xjpf $f --xattrs --exclude='./dev/*' || exit 4
}


# configure our 3 repositories and prepare 1 placeholder too
# the local repository rules always
#
function CompileRepoFiles()  {
  mkdir -p     ./etc/portage/repos.conf/
  cat << EOF > ./etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo

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
auto-sync = no
EOF

  cat << EOF > ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location  = /tmp/tb/data/portage
masters   = gentoo
auto-sync = no
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
auto-sync = no
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

j="1"
MAKEOPTS="-j\$j"
NINJAFLAGS="-j\$j"
EGO_BUILD_FLAGS="-p \$j"
GOMAXPROCS="\$j"
RUSTFLAGS="-C codegen-units=\$j"

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

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"

EOF
}


# create symlinks from /tmp/tb/data/** to the appropriate portage directories
# they become effective by the bind-mount of ~/tb onto /tmp/tb within chr.sh
#
function CompilePortageFiles()  {
  mkdir tmp/tb  # bind mount point of the tinderbox directory got from the host

  # create portage directories and symlinks
  #
  mkdir ./usr/portage
  mkdir ./var/tmp/{distfiles,portage}

  for d in package.{accept_keywords,env,mask,unmask,use} env profile
  do
    [[ ! -d ./etc/portage/$d ]] && mkdir ./etc/portage/$d
    chmod 777 ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../tmp/tb/data/patches)

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    (cd ./etc/portage/$d && ln -s ../../../tmp/tb/data/$d.common common)
  done

  for d in package.{accept_keywords,unmask}
  do
    (cd ./etc/portage/$d && ln -s ../../../tmp/tb/data/$d.$keyword $keyword)
  done

  touch       ./etc/portage/package.mask/self     # contains failed package at this image
  chmod a+rw  ./etc/portage/package.mask/self

  touch      ./etc/portage/package.use/setup      # USE flags added at setup
  chmod a+rw ./etc/portage/package.use/setup

  # activate at every n-th image predefined USE flag sets
  #
  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    (cd ./etc/portage/package.use && ln -s ../../../tmp/tb/data/package.use.ff-and-tb ff-and-tb)
  fi

  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    (cd ./etc/portage/package.use && ln -s ../../../tmp/tb/data/package.use.ffmpeg ffmpeg)
  fi

  echo "*/* $(cpuid2cpuflags)" > ./etc/portage/package.use/00cpuflags

  # create package specific env files
  #
  cat << EOF > ./etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CXXFLAGS -g -ggdb"
FEATURES="splitdebug"
EOF

  # build w/o tests for packages listed in package.env/* with the keyword "notest"
  #
  echo 'FEATURES="-test"'                   > ./etc/portage/env/notest

  # breakage is forced in job.sh by the XDG_* variables
  #
  echo 'FEATURES="-sandbox"'                > ./etc/portage/env/nosandbox

  # dito
  #
  echo 'FEATURES="-usersandbox"'            > ./etc/portage/env/nousersandbox
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


# update_backlog.sh writes into the backlog.upd
# job,sh writes into backlog.1st
# the default backlog is only shrinked after setup
#
function CreateBacklog()  {
  backlog=./tmp/backlog

  truncate -s 0 $backlog{,.1st,.upd}
  chmod a+w $backlog{,.1st,.upd}

  qsearch --all --nocolor --name-only --quiet | sort --random-sort >> $backlog

  if [[ -e $origin ]]; then
    # no replay of @sets or %commands, just packages
    # the history file contains also all failed tasks, but that doesn't hurt
    # we intentionally don't want the output of `qlist -ICv` here
    #
    echo "INFO finished replay of task history of $origin"    >> $backlog.1st
    grep -v -E "^(%|@)" $origin/tmp/task.history | tac | uniq >> $backlog.1st
    echo "INFO starting replay of task history of $origin"    >> $backlog.1st
  fi

  cat << EOF >> $backlog.1st
@world
app-portage/pfl
app-portage/eix
@system
%emerge -u sys-kernel/gentoo-sources
EOF

  # switch to the other SSL vendor
  #
  if [[ "$libressl" = "y" ]]; then
    cp $(dirname $0)/switch2libressl.sh ./tmp/
    echo "%/tmp/switch2libressl.sh" >> $backlog.1st
  fi

  # update GCC asap after setup
  #
  cat << EOF >> $backlog.1st
%emerge -u sys-devel/gcc
sys-apps/sandbox
EOF

if [[ "$profile" =~ "systemd" ]]; then
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
  echo 'local' >            ./usr/local/portage/profiles/repo_name
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
#         <package>                   <command/s>
#         app-arch/sharutils          uudecode
#         app-portage/gentoolkit      equery eshowkw revdep-rebuild
#         app-portage/portage-utils   qlop
#         www-client/pybugz           bugz
# - try to auto-fix USE flags deps to let the first @system update succeed
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

emerge --noreplace net-misc/netifrc

emerge mail-mta/ssmtp || exit 7
emerge mail-client/mailx || exit 7
(cd /etc/ssmtp && ln -snf ../../tmp/tb/sdata/ssmtp.conf) || exit 7

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 8
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

image_dir=$(pwd)

if [[ "$image_dir" = "/home/tinderbox" ]]; then
  echo "you are in /home/tinderbox !"
  exit 3
fi

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# store the stage3 file in the distfiles directory
#
distfiles=/var/tmp/distfiles

# the remote stage3 location
#
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds
stage3=""

autostart="y"   # start the image after setup
origin=""       # clone from that origin image

while :
do
  SetOptions
  ComputeImageName
  if [[ $? -eq 0 || $# -ne 0 ]]; then
    break
  fi
done

UnpackStage3
ConfigureImage
EmergeMandatoryPackages

cd /home/tinderbox/run && ln -s ../$mnt || exit 11
echo " setup  OK: $name"

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
