#!/bin/sh
#
# set -x

# setup a new tinderbox image
#
# typical call:
#
# $> echo "sudo ~/tb/bin/tbs.sh" | at now + 10 min

# due to using sudo we need to define the path to $HOME
#
tbhome=/home/tinderbox

#############################################################################
#
# functions
#

# create a (r)andomized (U)SE (f)lag (s)ubset
#
function rufs()  {
  allflags="
    aes-ni alisp alsa aqua avcodec avformat btrfs bugzilla bzip2 cairo cdb
    cdda cddb cgi cgroups cjk clang compat consolekit contrib corefonts
    csc cups curl dbus dec_av2 declarative designer dnssec dot drmkms dvb
    dvd ecc egl eglfs emacs evdev exif ext4 extra extraengine fax ffmpeg
    filter fitz fluidsynth fontconfig fortran fpm freetds ftp gd gif git
    glamor gles gles2 gnomecanvas gnome-keyring gnuplot gnutls go gpg
    graphtft gstreamer gtk gtk2 gtk3 gtkstyle gudev gui gzip haptic havege
    hdf5 help ibus icu imap imlib infinality inifile introspection
    ipv6 isag jadetex javascript javaxml jpeg kerberos kvm lapack latex
    ldap libinput libkms libvirtd llvm logrotate lua luajit lvm lzma mad
    mbox mdnsresponder-compat melt midi mikmod minimal minizip mng mod
    modplug mono mp3 mp4 mpeg mpeg2 mpeg3 mpg123 mpi mssql mta mtp multimedia
    mysql mysqli natspec ncurses networking nscd nss obj objc odbc
    offensive ogg ois opencv openexr opengl openmpi openssl opus osc pam
    pcre16 perl php pkcs11 plasma plotutils plugins png policykit postgres
    postproc postscript printsupport pulseaudio pwquality pypy python qemu
    qml qt5 rdoc rendering ruby sasl scripts scrypt sddm sdl secure-delete
    semantic-desktop server smartcard smime smpeg snmp sockets source
    sourceview spice sql sqlite sqlite3 ssh ssh-askpass ssl svc svg
    swscale system-cairo system-ffmpeg system-harfbuzz system-icu
    system-jpeg system-libevent system-libs system-libvpx system-llvm
    system-sqlite szip tcl tcpd theora thinkpad threads timidity tk tls
    tools tracepath traceroute truetype udev udisks ufed uml usb usbredir
    utils uxa v4l v4l2 vaapi vala vdpau video vim vlc vorbis vpx wav
    wayland webgl webkit webstart widgets wma wxwidgets X x264 x265 xa xcb
    xetex xinerama xinetd xkb xml xmlreader xmp xscreensaver xslt xvfb
    xvmc xz zenmap ziffy zip zlib
  "
  # formatter: echo "$allflags" | xargs -n 1 | sort -u | xargs -s 76 | sed 's/^/    /g'
  #

  # (m)ask a flag with a likelihood of 1/m
  # or (s)et it with a likelihood of s/m
  # else don't mention it
  #
  m=50  # == 2%
  s=4   # == 8%

  for f in $(echo $allflags)
  do
    let "r = $RANDOM % $m"
    if [[ $r -eq 0 ]]; then
      echo -n " -$f"    # mask it

    elif [[ $r -le $s ]]; then
      echo -n " $f"     # set it
    fi
  done
}


# deduce our tinderbox image name from the profile and current stage3 file name
#
function ComputeImageName()  {
  if [[ "$profile" = "hardened/linux/amd64" ]]; then
    name="hardened"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "hardened/linux/amd64/no-multilib" ]]; then
    name="hardened-no-multilib"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened+nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "default/linux/amd64/13.0/no-multilib" ]]; then
    name="13.0-no-multilib"
    stage3=$(grep "^20....../stage3-amd64-nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$(basename $profile)" = "systemd" ]]; then
    name="$(basename $(dirname $profile))-systemd"
    stage3=$(grep "^20....../systemd/stage3-amd64-systemd-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  else
    name="$(basename $profile)"
    stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
  fi

  # don't mention the default to avoid too long image names
  #
  if [[ "$keyword" = "stable" ]]; then
    name="$name-$keyword"
  fi

  if [[ "$clang" = "y" ]]; then
    name="$name-clang"
  fi

  if [[ "$libressl" = "y" ]]; then
    name="$name-libressl"
  fi

  if [[ "$multilib" = "y" ]]; then
    name="$name-abi32+64"
  fi

  if [[ -n "$suffix" ]]; then
    name="$name-$suffix"
  fi

  name="${name}_$(date +%Y%m%d-%H%M%S)"
  echo " $imagedir/$name"
  echo
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  b=$(basename $stage3)
  f=/var/tmp/distfiles/$b
  if [[ ! -f $f || ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=/var/tmp/distfiles || exit 4
  fi

  gpg --quiet --verify $f.DIGESTS.asc || exit 4

  mkdir $name           || exit 4
  cd $name              || exit 4
  tar xjpf $f --xattrs  || exit 4
}


# configure 3 repositories amd prepare a placeholder too
#
function CompileRepoFiles()  {
  # the local repository rules always
  #
  mkdir -p     etc/portage/repos.conf/
  cat << EOF > etc/portage/repos.conf/default.conf
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

  cat << EOF > etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no
EOF

  cat << EOF > etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location  = /tmp/tb/data/portage
masters   = gentoo
auto-sync = no
EOF

  cat << EOF > etc/portage/repos.conf/foo.conf
#[foo]
#location  = /usr/local/foo
#auto-sync = yes
#sync-type = git
#sync-uri  = https://anongit.gentoo.org/git/proj/foo.git
EOF

  cat << EOF > etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
auto-sync = no
EOF
}


# compile make.conf now together
#
function CompileMakeConf()  {
  chmod a+w etc/portage/make.conf

  sed -i  -e '/^CFLAGS="/d'       \
          -e '/^CXXFLAGS=/d'      \
          -e '/^CPU_FLAGS_X86=/d' \
          -e '/^USE=/d'           \
          -e '/^PORTDIR=/d'       \
          -e '/^PKGDIR=/d'        \
          -e '/^#/d'              \
          -e '/^DISTDIR=/d'       \
          etc/portage/make.conf

# no -Werror=implicit-function-declaration: https://bugs.gentoo.org/show_bug.cgi?id=602960
#
  cat << EOF >> etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native -Wall"
CXXFLAGS="-O2 -pipe -march=native"

USE="
  pax_kernel ssp xtpax -bindist -cdinstall -oci8

$( echo $flags | xargs -s 78 | sed 's/^/  /g' )
$( if [[ "$clang" = "y" ]]; then echo "clang"; fi )
"

ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '~amd64' || echo 'amd64' )
$(/usr/bin/cpuinfo2cpuflags-x86)
PAX_MARKINGS="XT"

$( [[ "$multilib" = "y" ]] && echo '#ABI_X86="32 64"' )

$( [[ -n "$origin" ]] && grep "^L10N" $origin/etc/portage/make.conf || L10N="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)" )

ACCEPT_LICENSE="*"

MAKEOPTS="-j1"
NINJAFLAGS="-j1"

EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
CLEAN_DELAY=0

ALSA_CARDS="hda-intel"
INPUT_DEVICES="evdev synaptics"
VIDEO_CARDS="intel i965"

FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox -news"

DISTDIR="/var/tmp/distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"
EOF
}


# symlink the (shared) package files of /tmp/tb/data to the portage directories
#
function CompilePackageFiles()  {
  mkdir tmp/tb  # mount point of the tinderbox directory of the host

  # create portage directories and symlinks (becomes effective by the bind-mount of ~/tb)
  #
  mkdir usr/portage
  mkdir var/tmp/{distfiles,portage}

  for d in package.{accept_keywords,env,mask,unmask,use} env patches profile
  do
    mkdir     etc/portage/$d 2>/dev/null
    chmod 777 etc/portage/$d
  done

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    (cd etc/portage/$d; ln -s ../../../tmp/tb/data/$d.common common)
  done

  for d in package.{accept_keywords,unmask}
  do
    (cd etc/portage/$d; ln -s ../../../tmp/tb/data/$d.$keyword $keyword)
  done

  touch       etc/portage/package.mask/self     # failed package at this image
  chmod a+rw  etc/portage/package.mask/self

  if [[ "$clang" = "y" || "$keyword" = "unstable" && $(($RANDOM % 3)) -eq 0 || -f $origin/etc/portage/package.unmask/gcc-6 ]]; then
    # unmask GCC-6 : https://bugs.gentoo.org/show_bug.cgi?id=582084
    #
    v=$(ls /usr/portage/sys-devel/gcc/gcc-6.*.ebuild | xargs -n 1 basename | tail -n 1 | xargs -n 1 qatom | awk ' { print $3 } ')
    echo "sys-devel/gcc:$v"    > etc/portage/package.unmask/gcc-6
    echo "sys-devel/gcc:$v **" > etc/portage/package.accept_keywords/gcc-6
  fi

  echo "$profile" | grep -e "^hardened/"
  if [[ $? -eq 0 ]]; then
    cat << EOF >> etc/portage/package.mask/emacs
# https://bugs.gentoo.org/show_bug.cgi?id=602992
#
app-editors/emacs
app-editors/emacs-vcs
EOF
  fi

  touch      etc/portage/package.use/setup     # USE flags added during setup phase
  chmod a+rw etc/portage/package.use/setup

  # activate at every n-th image predefined USE flag sets (ffmpeg, firefox/thunderbird, etc) too
  #
  for f in {ff-and-tb,ffmpeg}
  do
    if [[ $(($RANDOM % 4)) -eq 0 ]]; then
      (cd etc/portage/package.use; ln -s ../../../tmp/tb/data/package.use.$f $f)
    fi
  done

  # support special environments for dedicated packages
  #
  cat << EOF > etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CXXFLAGS -g -ggdb"
FEATURES="splitdebug"
EOF

  # no special c++ flags (eg. revert -Werror=terminate)
  #
  echo 'CXXFLAGS="-O2 -pipe -march=native"' > etc/portage/env/cxx

  # force tests of entries defined in package.env.common
  #
  echo 'FEATURES="test"'                    > etc/portage/env/test

  # we force breakage with XDG_* settings in job.sh
  #
  echo 'FEATURES="-sandbox -usersandbox"'   > etc/portage/env/nosandbox

  # test known to be broken
  #
  echo 'FEATURES="test-fail-continue"'      > etc/portage/env/test-fail-continue

  # use gcc (instead clang)
  #
  echo -e "CC=gcc\nCXX=g++"                 > etc/portage/env/usegnucompiler
}


# DNS resolution + .vimrc
#
function CompileMiscFiles()  {
  cp -L /etc/hosts /etc/resolv.conf etc/

  cat << EOF > root/.vimrc
set softtabstop=2
set shiftwidth=2
set tabstop=2
set expandtab
EOF
}


# the last line is the first entry and so on
#
function FillPackageList()  {
  pks=tmp/packages

  if [[ -n "$origin" ]]; then
    cp $origin/$pks $pks
    # replay the emerge history
    #
    qlop --nocolor --list -f $origin/var/log/emerge.log 2>/dev/null | awk ' { print $7 } ' | xargs qatom | cut -f1-2 -d' ' | tr ' ' '/' > $pks.tmp
    echo "INFO $(wc -l < $pks.tmp) packages of origin $origin replayed" >> $pks
    # use the (remaining) package list from origin
    #
    tac $pks.tmp >> $pks
    rm $pks.tmp
  else
    # fully randomized package list
    #
    qsearch --all --nocolor --name-only --quiet | sort --random-sort > $pks
  fi

  # emerge/upgrade mandatory package/s and upgrade @system
  # the side effect of the last action (@world) is to prevent insert_pks.sh
  # from changing the package list before the setup is completed
  #
  cat << EOF >> $pks
# setup done
@world
app-text/wgetpaste
app-portage/pfl
app-portage/eix
@system
%BuildKernel
%rm -f /etc/portage/package.mask/setup_blocker
EOF

  # switch to an alternative SSL lib before @system is upgraded
  #
  if [[ "$libressl" = "y" ]]; then
    echo "%/tmp/tb/bin/switch2libressl.sh" >> $pks
  fi

  # prefix "%" is needed here due to IGNORE_PACKAGE
  #
  echo "%emerge -u sys-kernel/hardened-sources" >> $pks

  # switch to latest compiler asap
  #
  if [[ "$clang" = "y" ]]; then
    echo "%emerge -u sys-devel/clang" >> $pks
  fi
  echo "%emerge -u sys-devel/gcc" >> $pks

  chown tinderbox.tinderbox $pks
}


# repos.d/* , make.conf and all the stuff
#
function ConfigureImage()  {
  mkdir -p                  usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > usr/local/portage/metadata/layout.conf
  echo 'local' >            usr/local/portage/profiles/repo_name
  chown -R portage:portage  usr/local/portage/

  CompileRepoFiles
  CompileMakeConf
  CompilePackageFiles
  CompileMiscFiles
  FillPackageList
}


# create a shell script to:
#
# - configure locale, timezone, MTA etc
# - install and configure tools used in job.sh:
#         <package>                   <command/s>
#         app-arch/sharutils          uudecode
#         app-portage/gentoolkit      equery eshowkw revdep-rebuild
#         app-portage/portage-utils   qlop
#         www-client/pybugz           bugz
# - update sandbox if applicable
# . dry test of GCC
# - dry test of @system upgrade to auto-fix package-specific USE flags
#
function CreateSetupScript()  {
  dryrun="emerge --backtrack=100 --deep --update --changed-use --with-bdeps=y @system --pretend"
  perl_stable_version=$(portageq best_version / dev-lang/perl)

  cat << EOF > tmp/setup.sh
function ExitOnError() {
  echo "saving portage tmp files ..."
  cp -ar /var/tmp/portage /tmp
  exit \$1
}

eselect profile set $profile || exit 6

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

echo -e "# packages preventing the setup (tbs.sh) of this tinderbox image\n#\n" > /etc/portage/package.mask/setup_blocker
echo ">${perl_stable_version}" >> /etc/portage/package.mask/setup_blocker

emerge sys-apps/elfix || ExitOnError 6
migrate-pax -m

emerge mail-mta/ssmtp || ExitOnError 7
emerge mail-client/mailx || ExitOnError 7
(cd /etc/ssmtp && ln -snf ../../tmp/tb/sdata/ssmtp.conf .) || ExitOnError 7

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || ExitOnError 8
(cd /root && ln -snf ../tmp/tb/sdata/.bugzrc .) || ExitOnError 8

if [[ "$clang" = "y" ]]; then
  echo -e "CC=clang\nCXX=clang++" >> /etc/make.conf
fi

emerge -u sys-apps/sandbox || ExitOnError 8

emerge --update --pretend sys-devel/gcc || exit 9

rc=0
mv /etc/portage/package.mask/setup_blocker /tmp/
$dryrun &> /tmp/dryrun.log
if [[ \$? -ne 0 ]]; then
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u > /etc/portage/package.use/setup
  if [[ -s /etc/portage/package.use/setup ]]; then
    $dryrun &> /tmp/dryrun.log || rc=9
  else
    rc=9
  fi
fi
mv /tmp/setup_blocker /etc/portage/package.mask/

exit \$rc
EOF
}


# we need at least a working mailer and bugz
#
function EmergeMandatoryPackages() {
  CreateSetupScript

  # <app-admin/eselect-1.4.7 $LANG issue
  #
  if [[ "$(qlist -ICv app-admin/eselect | xargs -n 1 qatom | cut -f3 -d' ')" = "1.4.5" ]]; then
    (
      cd usr/share/eselect

      wget -q -O- https://598480.bugs.gentoo.org/attachment.cgi?id=451903 2>/dev/null |\
      sed 's,/libs/config.bash.in,/libs/config.bash,g' |\
      patch -p1 --forward
    )
    if [[ $? -ne 0 ]]; then
      exit 10
    fi
  fi

  cd ..
  $(dirname $0)/chr.sh $name '/bin/bash /tmp/setup.sh &> /tmp/setup.log'
  rc=$?

  # try to shorten the link to the image, eg.: img1/plasma-...
  #
  cd $tbhome
  d=$(basename $imagedir)/$name
  if [[ ! -d $d ]]; then
    d=$imagedir/$name
  fi

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $d"

    if [[ $rc -eq 9 ]]; then
      echo
      cat $d/tmp/dryrun.log
    else
      echo
      cat $d/tmp/setup.log
    fi

    # the usage of "~" is here ok b/c usually those commands are
    # manually run by the user "tinderbox"
    #
    echo
    echo "    view $d/tmp/dryrun.log"
    echo "    vi $d/etc/portage/make.conf"
    echo "    sudo ~/tb/bin/chr.sh $d '  $dryrun  '"
    echo "    (cd ~/run && ln -s ../$d)"
    echo "    ~/tb/bin/start_img.sh $name"
    echo

    exit $rc
  fi

  (cd $tbhome/run && ln -s ../$d) || exit 11

  echo
  echo " setup  OK : $d"
  echo
}


#############################################################################
#
# main
#
if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# the remote stage3 location
#
imagedir=$(pwd)
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds
latest=latest-stage3.txt

autostart="y"   # start the image after setup ?
clang="n"       # prefer CLANG over GCC
flags=$(rufs)   # holds the current USE flag subset
origin=""       # clone from another image ?
suffix=""       # will be appended onto the name before the timestamp

# pre-select profile, keyword, ssl vendor and ABI_X86
#
profile=$(eselect profile list | awk ' { print $2 } ' | grep -v -E 'kde|x32|selinux|musl|uclibc|profile|developer' | sort --random-sort | head -n1)

keyword="unstable"

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  libressl="y"
else
  libressl="n"
fi

if [[ "$keyword" = "stable" ]]; then
  libressl="n"
fi

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  multilib="y"
else
  multilib="n"
fi

echo "$profile" | grep -q 'no-multilib'
if [[ $? -eq 0 ]]; then
  multilib="n"
fi

# the caller can overwrite the (thrown) settings now
#
while getopts a:c:f:k:l:m:o:p:s: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;

    c)  clang="$OPTARG"
        if [[ "$clang" != "y" && "$clang" != "n" ]]; then
          echo " wrong value for \$clang: $clang"
          exit 2
        fi
        keyword="unstable"
        ;;

    f)  if [[ -f "$OPTARG" ]] ; then
          # USE flags are either defined as USE="..." or justed listed
          #
          flags="$(source $OPTARG; echo $USE)"
          if [[ -z "$flags" ]]; then
            flags="$(cat $OPTARG)"
          fi
        else
          flags="$OPTARG"
        fi
        ;;

    k)  keyword="$OPTARG"
        if [[ "$keyword" != "stable" && "$keyword" != "unstable" ]]; then
          echo " wrong value for \$keyword: $keyword"
          exit 2
        fi
        ;;

    l)  libressl="$OPTARG"
        if [[ "$libressl" != "y" && "$libressl" != "n" ]]; then
          echo " wrong value for \$libressl: $libressl"
          exit 2
        fi
        ;;

    m)  multilib="$OPTARG"
        if [[ "$multilib" != "y" && "$multilib" != "n" ]]; then
          echo " wrong value for \$multilib $multilib"
          exit 2
        fi
        ;;

    o)  origin="$OPTARG"
        if [[ ! -e $origin ]]; then
          echo "\$origin '$origin' doesn't exist!"
          exit 2
        fi

        profile=$(readlink $origin/etc/portage/make.profile | cut -f6- -d'/')
        flags="$(source $origin/etc/portage/make.conf; echo $USE)"

        grep -q '^CURL_SSL="libressl"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
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

        grep -q '#ABI_X86="32 64"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          multilib="y"
        else
          multilib="n"
        fi
        ;;

    p)  profile="$OPTARG"
        if [[ ! -d /usr/portage/profiles/$profile ]]; then
          echo " profile unknown: $profile"
          exit 2
        fi
        ;;

    s)  suffix="$OPTARG"
        ;;

    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 2
        ;;
  esac
done

#############################################################################
#
if [[ "$tbhome" = "$imagedir" ]]; then
  echo "you are in \$tbhome !"
  exit 3
fi

wget --quiet $wgethost/$wgetpath/$latest --output-document=$tbhome/$latest
if [[ $? -ne 0 ]]; then
  echo " wget failed of: $latest"
  exit 3
fi

ComputeImageName          &&\
UnpackStage3              &&\
ConfigureImage            &&\
EmergeMandatoryPackages

if [[ "$autostart" = "y" ]]; then
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
else
  echo "no autostart choosen - run sth. like:  start_img.sh $name"
fi

exit 0
