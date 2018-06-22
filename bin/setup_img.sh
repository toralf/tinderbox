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

# throw up to n-1 USE flags, up to m-1 of them are masked
#
function ThrowUseFlags()  {
  n=80
  m=20

  grep -h -v -e '^$' -e '^#' -e 'internal use only' -e 'DO NOT USE THIS' /usr/portage/profiles/use{,.local}.desc |\
  cut -f2 -d ':' |\
  cut -f1 -d ' ' |\
  egrep -v -e '32|64|^armv|bindist|build|cdinstall|debug|gallium|gcj|hostname|kill|linguas|make-symlinks|minimal|monolithic|multilib|musl|nvidia|oci8|opencl|pax|prefix|qt4|tools|selinux|ssl|static|symlink|systemd|test|uclibc|vaapi|vdpau|vim-syntax|vulkan' |\
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
# set variables to arbitrarily choosen values
# might be overwritten by command line parameter
#
function SetOptions() {
  autostart="y"   # start the image after setup
  origin=""       # clone from the specified image

  # choose one of 17.0/*
  #
  profile=$(eselect profile list | awk ' { print $2 } ' | grep -e "^default/linux/amd64/17.0" | cut -f4- -d'/' -s | grep -v -e '/x32' -e '/musl' -e '/selinux' | sort --random-sort | head -n 1)

  # no automatic check of stable amd64
  #
  keyword="unstable"

  # alternative SSL vendor: LibreSSL
  #
  libressl="n"
  if [[ $(($RANDOM % 3)) -eq 0 ]]; then
    libressl="y"
  fi

  # ABI_X86="32 64"
  #
  multilib="n"
  if [[ ! $profile =~ "no-multilib" ]]; then
    if [[ $(($RANDOM % 8)) -eq 0 ]]; then
      multilib="y"
    fi
  fi

  # suffix of the image name
  #
  suffix=""

  # FEATURES=test
  #
  testfeature="n"
  if [[ "$keyword" != "stable" ]]; then
    if [[ $(($RANDOM % 20)) -eq 0 ]]; then
      testfeature="y"
    fi
  fi
}


# helper of main()
#
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


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  latest=$distfiles/latest-stage3.txt
  wget --quiet $wgethost/$wgetpath/latest-stage3.txt --output-document=$latest || exit 3

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
    exit 3
  fi

  f=$distfiles/$(basename $stage3)
  if [[ ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=$distfiles
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "can't download stage3 file '$stage3' of profile '$profile', rc=$rc"
      rm -f $f{,.DIGESTS.asc}
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

  cd $name || exit 4
  tar -xpf $f --xattrs --exclude='./dev/*' || exit 4
}


# configure 3 repositories and prepare 1 additional (foo)
# the local repository rules
# the first 3 are synced outside of the image
# [foo] should be synced in job.sh as a daily task
#
function CompileRepoFiles()  {
  mkdir -p      ./etc/portage/repos.conf/
  cat << EOF >> ./etc/portage/repos.conf/default.conf
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

  cat << EOF >> ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
EOF

  cat << EOF >> ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location  = /tmp/tb/data/portage
masters   = gentoo
EOF

  cat << EOF >> ./etc/portage/repos.conf/foo.conf
#[foo]
#location  = /usr/local/foo
#auto-sync = yes
#sync-type = git
#sync-uri  = https://anongit.gentoo.org/git/proj/foo.git
EOF

  cat << EOF >> ./etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
EOF
}


# modify make.conf from stage3
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

  # the "tinderbox" user had to put in group "portage" to make this effective
  #
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf

  features="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox cgroup -news"
  if [[ -e $origin/etc/portage/make.conf ]]; then
    l10n=$(grep "^L10N=" $origin/etc/portage/make.conf | cut -f2- -d'=' -s)
  else
    l10n="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  cat << EOF >> ./etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="\${CFLAGS}"

USE="
$( echo $useflags | xargs -s 78 | sed 's/^/  /g' )

  ssp -cdinstall -oci8 -pax_kernel -valgrind -symlink
"

# needed b/c the host is hardened, otherwise we'd get errors like:  Failed to set XATTR_PAX markings -me python.
#
PAX_MARKINGS="none"

$( [[ "$multilib" = "y" ]] && echo 'ABI_X86="32 64"' )
ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '"~amd64"' || echo '"amd64"' )

FEATURES="$features"
# do not compress logs in favour of a faster (manual made) grep
#
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
# althought we do not use portages mail functionality currently
# this variable is read by job.sh to derive the image name
#
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="http://mirror.netcologne.de/gentoo/ http://ftp.halifax.rwth-aachen.de/gentoo/ http://ftp.uni-erlangen.de/pub/mirrors/gentoo http://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/"

# https://bugs.gentoo.org/640930
#
FETCHCOMMAND="\${FETCHCOMMAND} --continue"

QEMU_SOFTMMU_TARGETS="x86_64 i386"
QEMU_USER_TARGETS="x86_64 i386"

EOF
}


# create portage directoriesa nd symlink or copy
# /tmp/tb/data/<files> to the appropriate target dirs respectively
#
function CompilePortageFiles()  {
  mkdir ./tmp/tb ./usr/portage ./var/tmp/distfiles ./var/tmp/portage 2>/dev/null

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

  # force "test" for dedicated packages
  #
  echo 'FEATURES="test"'          > ./etc/portage/env/test

  # build w/o "test", useful if package specific test phase is known to be br0ken or takes too long
  #
  echo 'FEATURES="-test"'         > ./etc/portage/env/notest

  # at 2nd attempt to emerge a package do ignore the test phase result
  #
  echo 'FEATURES="test-fail-continue"'  > ./etc/portage/env/test-fail-continue

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
NINJAFLAGS="-j1"
EGO_BUILD_FLAGS="-p 1"
GOMAXPROCS="1"
GO19CONCURRENTCOMPILATION=0
RUSTFLAGS="-C codegen-units=1"
RUST_TEST_THREADS=1
RUST_TEST_TASKS=1
EOF

  echo '*/* noconcurrent'         > ./etc/portage/package.env/noconcurrent

  if [[ "$libressl" = "y" ]]; then
    # will be activated after GCC update
    #
    cat << EOF > ./tmp/00libressl
*/*               libressl -gnutls -openssl
net-misc/curl     curl_ssl_libressl -curl_ssl_gnutls -curl_ssl_openssl
EOF
  fi

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    cp /home/tinderbox/tb/data/$d.common                ./etc/portage/$d/common
  done

  for d in package.{accept_keywords,unmask}
  do
    cp /home/tinderbox/tb/data/$d.$keyword              ./etc/portage/$d/$keyword
  done

  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    cp /home/tinderbox/tb/data/package.use.ff-and-tb    ./etc/portage/package.use/ff-and-tb
  fi

  if [[ $(($RANDOM % 8)) -eq 0 ]]; then
    cp /home/tinderbox/tb/data/package.use.ffmpeg       ./etc/portage/package.use/ffmpeg
  fi

  if [[ "$testfeature" = "y" ]]; then
    cp /home/tinderbox/tb/data/package.use.00test       ./etc/portage/package.use/00test
  fi

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/*
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/*
}


# configure DNS and vim (eg.: avoid interactive question)
#
function CompileMiscFiles()  {
  # resolve hostname to "127.0.0.1" or "::1" respectively
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

  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0
EOF
}


# /tmp/backlog.upd : update_backlog.sh will write to it
# /tmp/backlog     : nothing should write to it after setup
# /tmp/backlog.1st : filled during setup, job.sh writes to it
#
function CreateBacklog()  {
  backlog=./tmp/backlog

  truncate -s 0 $backlog{,.1st,.upd}
  chmod ug+w    $backlog{,.1st,.upd}
  chown tinderbox:portage $backlog{,.1st,.upd}

  qsearch --all --nocolor --name-only --quiet | sort --random-sort >> $backlog

  if [[ -e $origin ]]; then
    # no replay of @sets or %commands, just of the tasks
    # we intentionally don't want to replay `qlist -ICv`
    #
    echo "INFO finished replay of task history of $origin"    >> $backlog.1st
    grep -v -E "^(%|@)" $origin/tmp/task.history | tac | uniq >> $backlog.1st
    echo "INFO starting replay of task history of $origin"    >> $backlog.1st
  fi

  # last step: update @system and @world
  #
  cat << EOF >> $backlog.1st
@world
@system
EOF

  # asturm: give media-libs/jpeg a fair chance
  #
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    echo "media-libs/jpeg" >> $backlog.1st
  fi

  # switch to LibreSSL before upgrading @system
  #
  if [[ "$libressl" = "y" ]]; then
    # @preserved-rebuild will be scheduled by the unmerge of openssl
    # and will be added before "%emerge @preserved-rebuild" which must not fail eventually
    #
    cat << EOF >> $backlog.1st
%emerge @preserved-rebuild
%emerge -C openssl
%emerge -f dev-libs/libressl net-misc/openssh mail-mta/ssmtp net-misc/wget dev-lang/python
%mv /tmp/00libressl /etc/portage/package.use/
EOF
  fi

  # systemd needs kernel sources and would complain in the next @preserved-rebuild
  #
  # use % here b/c IGNORE_PACKAGES contains sys-kernel/*
  #
  echo "%emerge -u sys-kernel/vanilla-sources" >> $backlog.1st

  # upgrade GCC first
  #   %...  : bail out if that fails
  #   no --deep, that would result effectively in @system
  #
  echo "%emerge -u sys-devel/gcc" >> $backlog.1st

  # the systemd stage4 would have this done already
  #
  if [[ $profile =~ "systemd" ]]; then
    echo "%systemd-machine-id-setup" >> $backlog.1st
  fi
}


# portage releated files, DNS etc
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
  cat << EOF >> ./tmp/setup.sh
#!/bin/sh
#

# eselect sometimes can't be used for new unstable profiles
#
cd /etc/portage
ln -snf ../../usr/portage/profiles/default/linux/amd64/$profile make.profile || exit 6

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data || exit 6

echo "
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen -j1 || exit 6
eselect locale set en_US.UTF-8 || exit 6

if [[ $profile =~ "systemd" ]]; then
  echo 'LANG="en_US.UTF-8"' > /etc/locale.conf
fi

env-update
source /etc/profile

emerge mail-mta/ssmtp || exit 7
emerge mail-client/mailx || exit 7
# contains credentials
#
(cd /etc/ssmtp && ln -sf ../../tmp/tb/sdata/ssmtp.conf) || exit 7

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || exit 8
# contains credentials
#
(cd /root && ln -s ../tmp/tb/sdata/.bugzrc) || exit 8

if [[ "$testfeature" = "y" ]]; then
  sed -i -e 's/FEATURES="/FEATURES="test /g' /etc/portage/make.conf
else
  sed -i -e 's/FEATURES="/FEATURES="-test /g' /etc/portage/make.conf
fi

# the very first @system must succeed
#
$dryrun &> /tmp/dryrun.log
if [[ \$? -ne 0 ]]; then
  exit 9
fi

exit 0

EOF
}


# MTA, bugz etc are needed
#
function EmergeMandatoryPackages() {
  cd /home/tinderbox/

  $(dirname $0)/chr.sh $mnt '/bin/bash /tmp/setup.sh &> /tmp/setup.sh.log'
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

    # put helpful commands into the body for an easy copy+paste
    #
    echo "
      view ~/$mnt/tmp/dryrun.log
      echo '' >> ~/$mnt/etc/portage/package.use/setup

      sudo $(dirname $0)/chr.sh $mnt ' $dryrun '

      (cd ~/run && ln -s ../$mnt)
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
if [[ $# -gt 0 ]]; then
  echo " additional args: '${@}'"
fi
echo

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

useflags=$(ThrowUseFlags)
i=0
while :;
do
  ((i=i+1))
  SetOptions
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

          if [[ -f /etc/portage/package.use/00libressl ]]; then
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
      p)  profile="$(echo $OPTARG | sed -e 's,^/*,,' -e 's,/*$,,')"  # trim leading + trailing "/"
          ;;
      s)  suffix="$OPTARG"
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

  echo -n "."
  CheckOptions
  ComputeImageName

  # 11 profiles x 2^4
  #
  if [[ $i -gt 176 ]]; then
    echo "can't get a unique image name, will take $name"
    break
  fi

  # test that there's no similar image in ~/run
  #
  ls -d /home/tinderbox/run/${name}_????????-?????? &>/dev/null
  if [[ $? -ne 0 ]]; then
    # check running images too (parallel running instance of this script)
    #
    grep -q "${name}_" /proc/mounts
    if [[ $? -ne 0 ]]; then
      break
    fi
  fi
done
echo

# append the timestamp onto the name
#
name="${name}_$(date +%Y%m%d-%H%M%S)"
mkdir $name || exit 2

# relative path to the HOME directory of the tinderbox user
#
mnt=$(pwd | sed 's,/home/tinderbox/,,g')/$name
break

echo " $mnt"
echo

# location of the stage3 file
#
distfiles=/var/tmp/distfiles

# the remote stage3 location
#
wgethost=http://ftp.halifax.rwth-aachen.de/gentoo/
wgetpath=/releases/amd64/autobuilds

dryrun="emerge --update --newuse --changed-use --changed-deps=y --deep @system --pretend"

UnpackStage3            || exit 5
ConfigureImage          || exit 5
CreateSetupScript       || exit 5
EmergeMandatoryPackages || exit 5

cd /home/tinderbox/run && ln -s ../$mnt || exit 11
echo " setup  OK: $name"

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
