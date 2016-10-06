#!/bin/sh
#
# set -x

# setup a new tinderbox chroot image
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
# (m)ask   a flag with a likelihood of 1/m
# or (s)et a flag with a likelihood of 1/s
# else flag is unchanged (likelihood: 1 - 1/m -1/s)
#
function rufs()  {
  # echo $allflags | xargs -n 1 | sort -u | xargs -s 76 | sed 's/^/    /g'
  #
  allflags="
    aes-ni alisp alsa apache apache2 avcodec avformat btrfs bugzilla bzip2
    cairo cdb cdda cddb cgi cgroups clang compat consolekit contrib
    corefonts csc cups curl custom-cflags custom-optimization dbus
    dec_av2 declarative designer dnssec dot drmkms dvb dvd ecc egl eglfs
    emacs evdev exif ext4 extra extraengine ffmpeg fitz fluidsynth fontconfig
    fortran fpm freetds ftp gcj gd gif git glamor gles gles2 gnomecanvas
    gnome-keyring gnuplot gnutls gpg graphtft gstreamer gtk gtk2 gtk3
    gtkstyle gudev gui gzip haptic havege hdf5 help hpn ibus icu imap
    imlib infinality inifile introspection ipv6 isag ithreads jadetex
    javascript javaxml jpeg kerberos kvm lapack latex ldap libinput libkms
    libvirtd llvm logrotate lvm lzma mad mbox mdnsresponder-compat melt
    midi mikmod minimal minizip mng mod modplug mp3 mp4 mpeg mpeg2 mpeg3
    mpg123 mpi mssql mta multimedia multitarget mysql mysqli ncurses
    networking nls nscd nss obj objc odbc offensive ogg ois opencv openexr
    opengl openmpi openssl opus osc pam pcre16 pdo php pkcs11 plasma
    plotutils png policykit postgres postproc postscript printsupport
    pulseaudio pwquality pyqt4 python qemu qml qt3support qt4 qt5 rdoc
    rendering sasl scripts scrypt sddm sdl semantic-desktop server
    smartcard smime smpeg snmp sockets source sourceview spice sql sqlite
    sqlite3 ssh ssh-askpass ssl sslv2 sslv3 ssp svg swscale system-cairo
    system-ffmpeg system-harfbuzz system-icu system-jpeg system-libevent
    system-libs system-libvpx system-llvm system-sqlite szip tcl tcpd
    theora thinkpad threads timidity tk tls tools tracepath traceroute
    truetype udisks ufed uml usb usbredir utils uxa v4l v4l2 vaapi vala
    vdpau video vim vlc vorbis vpx wav wayland webgl webkit webstart
    widgets wma wxwidgets X x264 x265 xa xcb xetex xinerama xinetd xkb xml
    xmlreader xmp xscreensaver xslt xvfb xvmc xz zenmap ziffy zip zlib
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


# enlarge $name except a timestamp and set $stage3
#
function ComputeImageName()  {
  name="amd64"
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

  if [[ "$libressl" = "y" ]]; then
    name="$name-libressl"
  fi

  if [[ -n "$suffix" ]]; then
    name="$name-$suffix"
  fi

  name="$name-$mask"
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  b=$(basename $stage3)
  f=/var/tmp/distfiles/$b
  if [[ ! -f $f || ! -s $f ]]; then
    wget --quiet --no-clobber $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=/var/tmp/distfiles || exit 6
  fi

  gpg --quiet --verify $f.DIGESTS.asc || exit 7

  cd $imagedir  || exit 8
  mkdir $name   || exit 9
  cd $name
  tar xjpf $f --xattrs || exit 10
}


# configure repos.d/* files, make.conf and other stuff
#
function CompilePortageFiles()  {
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

  cat << EOF > etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no

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
  ssp

$(echo $flags | xargs -s 78 | sed 's/^/  /g')
"

ACCEPT_KEYWORDS=$( [[ "$mask" = "unstable" ]] && echo -n '~amd64' || echo 'amd64' )
$(/usr/bin/cpuinfo2cpuflags-x86)
PAX_MARKINGS="XT"

L10N="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"

SSL_BITS=4096

# we do only compile-tests
#
ACCEPT_LICENSE="*"

# parallel make issues aren't reliable reproducible and therefore out of the scope of the tinderbox
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

  mkdir tmp/tb  # mount point of the tinderbox directory of the host

  # create portage directories and symlink commonly used files into them
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

  touch       etc/portage/package.mask/self     # failed package at this image
  chmod a+rw  etc/portage/package.mask/self

  if [[ "$mask" = "unstable" ]]; then
    # unmask ffmpeg-3 at 2/3 of all unstable images
    #
    if [[ $(($RANDOM % 3)) -ne 0 ]]; then
      echo "media-video/ffmpeg" > etc/portage/package.unmask/ffmpeg
    fi

    # unmask GCC-6 per request of Soap
    #
    echo "sys-devel/gcc:6.2.0"    > etc/portage/package.unmask/gcc-6
    echo "sys-devel/gcc:6.2.0 **" > etc/portage/package.accept_keywords/gcc-6
  fi

  touch      etc/portage/package.use/setup     # USE flags added during setup phase
  chmod a+rw etc/portage/package.use/setup

  # xemacs hangs at hardened: https://bugs.gentoo.org/show_bug.cgi?id=540818
  #
  echo $profile | grep -q "hardened"
  if [[ $? -eq 0 ]]; then
    echo -e "app-editors/xemacs\napp-xemacs/*" > etc/portage/package.mask/xemacs
  fi

  # define special environments for dedicated packages
  # have a look into package.env.common
  #
  cat << EOF > etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CXXFLAGS -g -ggdb"
FEATURES="splitdebug"

EOF

  echo 'FEATURES="test"'                  > etc/portage/env/test
  echo 'FEATURES="-sandbox -usersandbox"' > etc/portage/env/nosandbox
}


# DNS resolution, and .vimrc
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


# add few mandatory tasks to the list too
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

  # first task: switch to latest GCC
  #
  cat << EOF >> $pks
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

eselect profile set $profile || exit \$?

echo "en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen

. /etc/profile
locale-gen                    || exit \$?
eselect locale set en_US.utf8 || exit \$?
. /etc/profile

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data
emerge --noreplace net-misc/netifrc

echo "=sys-libs/ncurses-6.0-r1" >  /etc/portage/package.mask/upgrade_blocker

emerge sys-apps/elfix || exit \$?
migrate-pax -m

# our SMTP mailer
#
emerge mail-mta/ssmtp || exit \$?

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
emerge mail-client/mailx || exit \$?

# install mandatory tools
#   <package>                   <command/s>
#
#   app-arch/sharutils          uudecode
#   app-portage/gentoolkit      equery eshowkw revdep-rebuild
#   app-portage/pfl             pfl
#   app-portage/portage-utils   qlop
#   www-client/pybugz           bugz
#
emerge app-arch/sharutils app-portage/gentoolkit app-portage/pfl app-portage/portage-utils www-client/pybugz || exit \$?

# we have "sys-kernel/" in IGNORE_PACKAGES therefore emerge kernel sources here
#
emerge sys-kernel/hardened-sources || exit \$?

rm /etc/portage/package.mask/upgrade_blocker

# auto-adapt the USE flags so that the very first @system isn't blocked
#
$dryrun &> /tmp/dryrun.log
rc=\$?
if [[ \$rc -ne 0 ]]; then
  rc=123
  # try to auto-fix the USE flags set
  #
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u > /etc/portage/package.use/setup
  # re-try it now
  #
  if [[ -s /etc/portage/package.use/setup ]]; then
    $dryrun &> /tmp/dryrun.log && rc=0
  fi
fi

if [[ "$libressl" = "y" ]]; then
  /tmp/tb/bin/switch2libressl.sh || exit \$?
fi

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

  # authentication avoids a 10 sec tarpitting delay by the hoster of our (mail) domain
  #
  grep "^Auth" /etc/ssmtp/ssmtp.conf >> $d/etc/ssmtp/ssmtp.conf

  # b.g.o. credentials
  #
  cp /home/tinderbox/.bugzrc $d/root

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $d"

    if [[ $rc -ne 123 ]]; then
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

  # create symlink to $HOME but only if the setup was successful
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

# the remote stage3 location
#
imagedir=$tbhome/images
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds
latest=latest-stage3.txt

autostart="y"   # start the chroot image after setup ?
flags=$(rufs)   # holds the current USE flag subset
libressl="n"
mask="unstable"
origin=""       # clone from another tinderbox image ?
profile=""
suffix=""       # free optional text

while getopts a:f:l:m:o:p:s: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;

    f)  if [[ -f "$OPTARG" ]] ; then
          # USE flags are either defined or just listed in a file
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
        if [[ "$mask" != "stable" && "$mask" != "unstable" ]]; then
          echo " wrong value for mask: $mask"
          exit 3
        fi
        ;;

    o)  origin="$OPTARG"
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
        if [[ ! -d /usr/portage/profiles/$profile ]]; then
          echo " profile unknown: $profile"
          exit 4
        fi
        ;;

    s)  suffix="$OPTARG"
        ;;

    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 2
        ;;
  esac
done

# fetch $latest here b/c it contains the stage3 file name which we derive in ComputeImageName()
#
wget --quiet $wgethost/$wgetpath/$latest --output-document=$tbhome/$latest
if [[ $? -ne 0 ]]; then
  echo " wget failed of: $latest"
  exit 3
fi

# arbitrarily choose a profile, keyword and libre/open ssl vendor
#
if [[ -z "$profile" ]]; then
  profiles=$(eselect profile list | awk ' { print $2 } ' | grep -v -E 'kde|x32|selinux|musl|uclibc|profile|developer' | sort --random-sort)
  while :;
  do
    for profile in $profiles
    do
      mask="unstable"
      libressl="n"

      # run not more than 2 systemd images
      #
      if [[ -n "$(echo $profile | grep 'systemd')" ]]; then
        if [[ $(ls -1d amd64-*-systemd-* 2>/dev/null | wc -l) -gt 1 ]]; then
          continue
        fi
      fi

      # run always 1 stable image
      #
      if [[ $(ls -1d amd64-*-stable_* 2>/dev/null | wc -l) -eq 0 ]]; then
        mask="stable"
      else
        # switch at every n-th unstable image to libressl
        #
        if [[ $(($RANDOM % 4)) -eq 0 ]]; then
          # plasma (QT) is not libressl ready
          #
          if [[ -z "$(echo $profile | grep 'plasma')" ]]; then
            libressl="y"
          fi
        fi
      fi
      ComputeImageName

      # do not run 2 nearly similar images (well, the USE flag set and the package list do differ always)
      #
      ls -1d $tbhome/${name}_20??????-?????? &>/dev/null || break 2
    done
  done

else
  ComputeImageName
fi

name="${name}_$(date +%Y%m%d-%H%M%S)"
echo " $imagedir/$name"
echo

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
