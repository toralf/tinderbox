#!/bin/sh
#
# set -x

# setup a new tinderbox chroot image
#
# typical call:
#
# $> echo "sudo ~/tb/bin/tbs.sh" | at now

# due to using sudo we need to define the path to $HOME
#
tbhome=/home/tinderbox

#############################################################################
#
# functions
#

# return a (r)andomized (U)SE (f)lag (s)ubset from the set stored in $flags
#
# (m)ask   a flag with a likelihood of 1/m
# or (s)et a flag with a likelihood of 1/s
# else flag is unchanged (likelihood: 1 - 1/m -1/s)
#
function rufs()  {
  # the USE flags we do consider
  # echo $allflags | xargs -n 1 | sort -u | xargs -s 76 | sed 's/^/    /g'
  #
  allflags="
    aes-ni alisp alsa apache apache2 avcodec avformat btrfs bugzilla bzip2
    cairo cdb cdda cddb cgi cgroups clang compat consolekit contrib
    corefonts csc cups curl custom-cflags custom-optimization cxx dbus
    dec_av2 declarative designer dnssec dot drmkms dvb dvd ecc egl eglfs
    emacs evdev exif ext4 extra extraengine ffmpeg fluidsynth fontconfig
    fortran fpm freetds ftp gcj gd gif git glamor gles gles2 gnomecanvas
    gnome-keyring gnuplot gnutls gpg graphtft gstreamer gtk gtk2 gtk3
    gtkstyle gudev gui gzip haptic havege hdf5 help hpn ibus icu imap imlib
    infinality inifile introspection ipv6 isag ithreads jadetex javascript
    javaxml jpeg kerberos kvm lapack latex ldap libinput libkms libvirtd
    llvm logrotate lvm lzma mad mbox mdnsresponder-compat melt midi mikmod
    minimal minizip mng mod modplug mp3 mp4 mpeg mpeg2 mpeg3 mpg123 mpi
    mssql mta multimedia multitarget mysql mysqli ncurses networking nls
    nscd nss obj objc odbc offensive ogg ois opencv openexr opengl openmpi
    openssl opus osc pam pcre16 pdo php pkcs11 plasma plotutils png
    policykit postgres postproc postscript printsupport pulseaudio
    pwquality pyqt4 python qemu qml qt3support qt4 qt5 rdoc rendering sasl
    scripts scrypt sddm sdl semantic-desktop server smartcard smime smpeg
    snmp sockets source sourceview spice sql sqlite sqlite3 ssh
    ssh-askpass ssl sslv2 sslv3 svg swscale system-cairo system-ffmpeg
    system-harfbuzz system-icu system-jpeg system-libevent system-libs
    system-libvpx system-llvm system-sqlite szip tcl tcpd theora thinkpad
    threads timidity tk tls tools tracepath traceroute truetype udisks
    ufed uml usb usbredir utils uxa v4l v4l2 vaapi vala vdpau video vim
    vlc vorbis vpx wav wayland webgl webkit webstart widgets wma wxwidgets
    X x264 x265 xa xcb xetex xinerama xinetd xkb xml xmlreader xmp
    xscreensaver xslt xvfb xvmc xz zenmap ziffy zip zlib
  "

  m=30
  s=6
  for f in $(echo $allflags)
  do
    let "r = $RANDOM % $m"
    if [[ $r -eq 0 ]]; then
      echo -n " -$f"
    elif [[ $r -le $s ]]; then
      echo -n " $f"
    fi
  done
}


# unpack the current stage3 file
#
function UnpackStage3()  {
  wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
  wgetpath=/releases/amd64/autobuilds
  latest=latest-stage3.txt

  wget --quiet $wgethost/$wgetpath/$latest --output-document=$tbhome/$latest
  if [[ $? -ne 0 ]]; then
    echo " wget failed: $latest"
    exit 4
  fi

  # $stage3 holds the full stage3 file name as found in $latest
  #
  if [[ "$profile" = "hardened/linux/amd64" ]]; then
    name="$name-hardened"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "hardened/linux/amd64/no-multilib" ]]; then
    name="$name-hardened-no-multilib"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened+nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "default/linux/amd64/13.0/no-multilib" ]]; then
    name="$name-13.0-no-multilib"
    stage3=$(grep "^20....../stage3-amd64-nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$(basename $profile)" = "systemd" ]]; then
    name="$name-$(basename $(dirname $profile))-systemd"
    stage3=$(grep "^20....../systemd/stage3-amd64-systemd-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  else
    name="$name-$(basename $profile)"
    stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
  fi

    if [[ -z "$stage3" ]]; then
    echo "couldn't derive stage3 filename !"
    exit 5
  fi

  # complete $name
  #
  if [[ "$libressl" = "y" ]]; then
    name="$name-libressl"
  fi
  if [[ -n "$suffix" ]]; then
    name="$name-$suffix"
  fi
  name="$name-$mask"
  name="${name}_$(date +%Y%m%d-%H%M%S)"
  echo " image: $name"
  echo

  # download stage3 if not already done
  #
  b=$(basename $stage3)
  f=/var/tmp/distfiles/$b
  if [[ ! -f $f || ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=/var/tmp/distfiles || exit 6
  fi

  # do always verify it
  #
  gpg --quiet --verify $f.DIGESTS.asc || exit 7

  cd $imagedir  || exit 8
  mkdir $name   || exit 9
  cd $name
  tar xjpf $f   || exit 10
}


# repos.d/, make.conf and all that stuff under /etc/portage/
#
function CompilePortageFiles()  {
  # https://wiki.gentoo.org/wiki/Overlay/Local_overlay
  #
  mkdir -p                  usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > usr/local/portage/metadata/layout.conf
  echo 'local' >            usr/local/portage/profiles/repo_name
  chown -R portage:portage  usr/local/portage/

  mkdir -p     etc/portage/repos.conf/
  cat << EOF > etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo

[gentoo]
priority = 1

[local]
priority = 2

EOF

  # stay at the "rsync" method for now, "git" would pull in too much deps (gitk etc.)
  #
  cat << EOF > etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no
#sync-type = rsync
#sync-uri  = rsync://rsync.de.gentoo.org/gentoo-portage/

EOF

  cat << EOF > etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
auto-sync = no

EOF

  # compile make.conf
  #
  m=etc/portage/make.conf
  chmod a+w $m

  sed -i  -e 's/^CFLAGS="/CFLAGS="-march=native /'  \
          -e '/^CPU_FLAGS_X86=/d'                   \
          -e '/^USE=/d'                             \
          -e '/^PORTDIR=/d'                         \
          -e '/^PKGDIR=/d'                          \
          -e '/^#/d'                                \
          -e 's#^DISTDIR=.*#DISTDIR="/var/tmp/distfiles"#' $m

  cat << EOF >> $m
USE="
  pax_kernel xtpax -cdinstall -oci8 -bindist

$(echo $flags | xargs -s 78 | sed 's/^/  /g')
"

ACCEPT_KEYWORDS=$( [[ "$mask" = "unstable" ]] && echo -n '~amd64' || echo 'amd64' )
$(/usr/bin/cpuinfo2cpuflags-x86)
PAX_MARKINGS="XT"

L10N="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"

SSL_BITS=4096

# just compile-tests
#
ACCEPT_LICENSE="*"

# parallel make issues aren't reliable reproducible
#
MAKEOPTS="-j1"
NINJAFLAGS="-j1"

EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
CLEAN_DELAY=0

# no "fail-clean", files would be cleaned before being picked up
#
FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox test-fail-continue -news"

PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa warn error"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"

EOF

  mkdir tmp/tb  # chr.sh will bind-mount onto here the tinderbox directory from the host

  # create portage directories and symlink them
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

  touch       etc/portage/package.mask/self     # hold all failed package at this image
  chmod a+rw  etc/portage/package.mask/self

  if [[ "$mask" = "unstable" ]]; then
    # unmask ffmpeg at 2 of 3 unstable images
    #
    if [[ $(($RANDOM % 3)) -ne 0 ]]; then
      echo "media-video/ffmpeg" > etc/portage/package.unmask/ffmpeg
    fi

    # GCC-6
    #
    echo "sys-devel/gcc:6.2.0"    > etc/portage/package.unmask/gcc-6
    echo "sys-devel/gcc:6.2.0 **" > etc/portage/package.accept_keywords/gcc-6
  fi

  touch      etc/portage/package.use/setup     # USE flags added by setup.sh or us
  chmod a+rw etc/portage/package.use/setup

  # emerging xemacs hangs at hardened: https://bugs.gentoo.org/show_bug.cgi?id=540818
  #
  echo $profile | grep -q "hardened"
  if [[ $? -eq 0 ]]; then
    echo -e "app-editors/xemacs\napp-xemacs/*" > etc/portage/package.mask/xemacs
  fi

  # upgrade blocker
  #
  echo "=sys-libs/ncurses-6.0-r1" >  etc/portage/package.mask/upgrade_blocker
  echo ">=dev-libs/gmp-6.1.0"     >> etc/portage/package.mask/upgrade_blocker

  # data/package.env.common contains the counterpart
  #
  cat << EOF > etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CFLAGS"
FEATURES="splitdebug"

EOF

  echo 'FEATURES="test"'                  > etc/portage/env/test
  echo 'FEATURES="-sandbox -usersandbox"' > etc/portage/env/nosandbox
}


# DNS resolution and VIM
#
function CompileMiscFiles()  {
  cp -L /etc/hosts /etc/resolv.conf etc/

  cat << EOF > root/.vimrc
set softtabstop=2
set shiftwidth=2
set tabstop=2

EOF
}


# first tasks: upgrade GCC first (if possible), build linux kernel, upgrade @system
#
function FillPackageList()  {
  pks=tmp/packages

  qsearch --all --nocolor --name-only --quiet | sort --random-sort > $pks

  # at least this INFO prevents insert_pkgs.sh from touching the package list too early
  #
  echo "INFO starting with the randomized package list" >> $pks

  if [[ -n "$origin" && -e $origin/var/log/emerge.log ]]; then
    qlop --nocolor --list -f $origin/var/log/emerge.log | awk ' { print $7 } ' | xargs qatom | cut -f1-2 -d' ' | tr ' ' '/' | tac >> $pks
    echo "INFO start of emerge history of $origin" >> $pks
  fi

  cat << EOF >> $pks
%rm -f /etc/portage/package.mask/upgrade_blocker
@system
%BuildKernel
sys-devel/gcc
EOF

  chown tinderbox.tinderbox $pks
}


# finalize setup of a chroot image
#
# - configure locale, timezone etc
# - install and configure tools used in job.sh
# - install kernel sources
# - dry test a @system upgrade
#
function EmergeMandatoryPackages() {
  dryrun="emerge --deep --update --changed-use --with-bdeps=y @system --pretend"

  cat << EOF > tmp/setup.sh

eselect profile set $profile || exit 1

echo "en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen

. /etc/profile
locale-gen || exit 1
eselect locale set en_US.utf8 || exit 1
. /etc/profile

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data
emerge --noreplace net-misc/netifrc

# avoid nano from being depcleaned after another editor is emerged too
#
emerge --noreplace app-editors/nano

emerge sys-apps/elfix || exit 2
migrate-pax -m

# our preferred simple mailer
#
emerge mail-mta/ssmtp || exit 3

echo "
root=tinderbox@zwiebeltoralf.de
MinUserId=9999
mailhub=mail.zwiebeltoralf.de:465
rewriteDomain=zwiebeltoralf.de
hostname=mr-fox.zwiebeltoralf.de
UseTLS=YES
" > /etc/ssmtp/ssmtp.conf

# our preferred MTA
#
emerge mail-client/mailx || exit 4

# install mandatory tools
#   <package>                   <command/s>
#
#   app-arch/sharutils          uudecode
#   app-portage/gentoolkit      equery eshowkw revdep-rebuild
#   app-portage/pfl             pfl
#   app-portage/portage-utils   qlop
#   www-client/pybugz           bugz
#
emerge app-arch/sharutils app-portage/gentoolkit app-portage/pfl app-portage/portage-utils www-client/pybugz || exit 5

# we have "sys-kernel/" in IGNORE_PACKAGES therefore emerge kernel sources here
#
emerge sys-kernel/hardened-sources || exit 6

if [[ "$libressl" = "y" ]]; then
  /tmp/tb/bin/switch2libressl.sh || exit \$?
fi

# auto-adapt the USE flags so that the very first @system isn't blocked
#
sed -i -e 's/^/#/g' /etc/portage/package.mask/upgrade_blocker
$dryrun &> /tmp/dryrun.log
rc=\$?
if [[ \$rc -ne 0 ]]; then
  # try to auto-fix the setup by fixing the USE flags set
  #
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u > /etc/portage/package.use/setup
  if [[ -s /etc/portage/package.use/setup ]]; then
    $dryrun &> /tmp/dryrun.log && rc=0 || rc=11
  else
    rc=12
  fi
fi
sed -i -e 's/#//g' /etc/portage/package.mask/upgrade_blocker

exit \$rc

EOF

  # installation takes about 1/2 hour
  #
  cd - 1>/dev/null

  $(dirname $0)/chr.sh $name '/bin/bash /tmp/setup.sh &> /tmp/setup.log'
  rc=$?

  cd $tbhome

  # strip off $tbhome
  #
  d=$(basename $imagedir)/$name

  # authentication avoids a 10 sec tarpitting delay by the Hoster
  #
  grep "^Auth" /etc/ssmtp/ssmtp.conf >> $d/etc/ssmtp/ssmtp.conf

  # b.g.o. credentials
  #
  cp /home/tinderbox/.bugzrc $d/root

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $d"

    if [[ $rc -ne 11 && $rc -ne 12 ]]; then
      echo
      cat $d/tmp/setup.log
    fi

    echo
    echo "    view $d/tmp/dryrun.log"
    echo "    vi $d/etc/portage/make.conf"
    echo "    sudo ~/tb/bin/chr.sh $d '$dryrun'"
    echo "    ln -s $d"
    echo "    ~/tb/bin/start_img.sh $name"
    echo

    exit $rc
  fi

  # create symlink to $HOME *iff* the setup was successful
  #
  ln -s $d || exit 11

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

autostart="y"                 # start the chroot image if setup was ok
origin=""                     # the origin to clone
flags=$(rufs)                 # create a (r)andomized (U)SE (f)lag (s)et
libressl="n"
if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  libressl="y"
fi
mask="unstable"
if [[ $(($RANDOM % 10)) -eq 0 ]]; then
  mask="stable"
fi
profile=$(eselect profile list | awk ' { print $2 } ' | grep -v -E 'kde|x32|selinux|musl|uclibc|profile|developer' | sort --random-sort | head -n1)
suffix=""

while getopts a:f:l:m:o:p:s: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;
    f)  if [[ -f "$OPTARG" ]] ; then
          # USE flags are either defined in another make.conf or just derived from a file
          #
          if [[ "$(basename $OPTARG)" = "make.conf" ]]; then
            flags="$(source $OPTARG; echo $USE)"
          else
            flags="$(cat $OPTARG)"
          fi
        else
          flags="$OPTARG"
          echo -e "\nWARN: read USE flags from command line !\n"
        fi
        ;;
    l)  libressl="$OPTARG"
        ;;
    m)  mask="$OPTARG"
        ;;
    o)  # an origin to clone from
        #
        origin="$OPTARG"
        if [[ ! -e $origin ]]; then
          echo "origin '$origin' to clone from doesn't exist!"
          exit 2
        fi
        profile=$(readlink $origin/etc/portage/make.profile | cut -f6- -d'/')
        flags="$(source $origin/etc/portage/make.conf; echo $USE)"
        grep -q 'CURL_SSL="libressl"' $origin/etc/portage/make.conf
        if [[ $? -eq 0 ]]; then
          libressl="y"
        fi
        grep -q '^ACCEPT_KEYWORDS=.*~amd64' $origin/etc/portage/make.conf
        if [[ $? -ne 0 ]]; then
          mask="stable"
        fi
        ;;
    p)  profile="$OPTARG"
        ;;
    s)  suffix="$OPTARG"
        ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 2
        ;;
  esac
done

if [[ "$mask" != "stable" && "$mask" != "unstable" ]]; then
  echo " wrong value for mask: $mask"
  exit 3
fi

if [[ -z "$profile" || ! -d /usr/portage/profiles/$profile ]]; then
  echo " profile unknown: $profile"
  exit 3
fi

imagedir="$tbhome/images"

# $name holds the directory/symlink name of the chroot image
# append <profile>, <mask> and <timestamp> onto this prefix too
#
name="amd64"

cd $tbhome

UnpackStage3
CompilePortageFiles
CompileMiscFiles
FillPackageList
EmergeMandatoryPackages

if [[ "$autostart" = "y" ]]; then
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
