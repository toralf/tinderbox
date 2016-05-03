#!/bin/sh
#
#set -x

# setup a new tinderbox chroot image
#

# typical call:
#
# $> echo "sudo ~/tb/bin/tbs.sh -A -m stable -i /home/tinderbox/images1 -p default/linux/amd64/13.0/desktop/plasma" | at now


# due to using sudo we need to define the path to $HOME
#
tbhome=/home/tinderbox


#############################################################################
#
# functions
#

# return a (r)andomized (U)SE (f)lag (s)ubset from the set $flags
#
# mask  a flag with a likelihood of 1/n
# set   a flag with a likelihood of 1/p
# empty else
#
function rufs()  {
  n=30
  let "p = n / 6"

  for f in $(echo $flags)
  do
    let "r = $RANDOM % $n"

    if [[ $r -eq 0 ]]; then
      echo -n " -$f"

    elif [[ $r -le $p ]]; then
      echo -n " $f"
    fi
  done
}

#############################################################################
#
# vars
#
name="amd64"         # fixed prefix, append later <profile>, <mask> and <timestamp>

e=(
  "default/linux/amd64/13.0"                \
  "default/linux/amd64/13.0/desktop"        \
  "default/linux/amd64/13.0/desktop/gnome"  \
  "default/linux/amd64/13.0/desktop/plasma" \
  "hardened/linux/amd64"                    \
)
profile=${e[$RANDOM % ${#e[@]}]}

e=(
  "stable"    \
  "unstable"  \
)
mask=${e[$RANDOM % ${#e[@]}]}

flags="
  aes-ni alisp alsa apache apache2 avcodec avformat avx avx2 btrfs bzip2
  cairo cdb cdda cddb cgi cgoups clang compat consolekit corefonts csc
  cups curl custom-cflags custom-optimization dbus dec_av2 declarative
  designer dnssec dot drmkms dvb dvd ecc egl eglfs evdev extraengine
  ffmpeg fontconfig fortran fpm freetds ftp gd gif git gles2 gnomecanvas
  gnome-keyring gnuplot gnutls gpg graphtft gstreamer gtk gtk3 gtkstyle
  gudev gui haptic havege hdf5 help icu imap imlib inifile introspection
  ipv6 isag ithreads jadetex javafx javascript javaxml jpeg kerberos kvm
  lapack ldap libkms libressl libvirtd llvm logrotate mbox
  mdnsresponder-compat melt mikmod minimal minizip mng mod modplug mssql
  multimedia multitarget mysql mysqli nscd nss obj objc odbc offensive
  ogg ois opencv openexr opengl openmpi openssl pcre16 pdo php pkcs11
  plasma png policykit postgres postproc postscript printsupport
  pulseaudio pwquality pyqt4 python qemu qml qt3support qt4 qt5 rdoc
  rendering scripts scrypt sddm sdl semantic-desktop server smartcard
  sockets source spice sql sqlite sqlite3 sse4 sse4_1 sse4_2 ssh-askpass
  ssl ssse3 svg swscale system-cairo system-ffmpeg system-harfbuzz
  system-icu system-jpeg system-libevent system-libs system-libvpx
  system-llvm system-sqlite szip tcl theora thinkpad threads tk tls
  tools truetype ufed uml usb usbredir uxa v4l v4l2 vaapi vdpau video
  vorbis vpx wav webkit webstart widgets wma wxwidgets x264 x265 xa
  xinetd xkb xml xmlreader xmp xscreensaver xslt xvfb xvmc xz zenmap zip
"
# echo $flags | xargs -n 1 | sort -u | xargs -s 76 | sed 's/^/  /g'
#
flags=$(rufs)

Start="n"           # start the chroot image if setup was successfully ?

let "i = $RANDOM % 2 + 1"
imagedir="$tbhome/images${i}"         # images[12]

#############################################################################
#
# main
#
cd $tbhome

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

while getopts Af:i:m:p: opt
do
  case $opt in
    A)  autostart="y"
        ;;
    f)  if [[ -f "$OPTARG" ]] ; then
          flags="$(cat $OPTARG)"
        else
          flags="$OPTARG"
        fi
        ;;
    i)  imagedir="$OPTARG"
        ;;
    m)  mask="$OPTARG"
        ;;
    p)  profile="$OPTARG"
        ;;
    *)  echo " '$opt' not implemented"
        exit 2
        ;;
  esac
done

if [[ ! "$mask" = "stable" && ! "$mask" = "unstable" ]]; then
  echo " wrong value for mask: $mask"
  exit 3
fi

if [[ ! -d /usr/portage/profiles/$profile ]]; then
  echo " profile unknown: $profile"
  exit 3
fi

if [[ ! -d $imagedir ]]; then
  echo " imagedir does not exist: $imagedir"
  exit 3
fi

# get the current stage3 file name
#
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds
latest=latest-stage3.txt

wget --quiet $wgethost/$wgetpath/$latest --output-document=$tbhome/$latest
if [[ $? -ne 0 ]]; then
  echo " wget failed: $latest"
  exit 4
fi

# $name holds the (directory) name of the chroot image (and will be symlinked into $HOME later)
# stage3 holds the full stage3 file name as found in file $latest
#
if [[ "$profile" = "hardened/linux/amd64" ]]; then
  name="$name-hardened"
  stage3=$(grep "^201...../hardened/stage3-amd64-hardened-201......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
else
  name="$name-$(basename $profile)"
  stage3=$(grep "^201...../stage3-amd64-201......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
fi

# now complete it with keyword and time stamp
#
name="$name-${mask}_$(date +%Y%m%d-%H%M%S)"
echo " name: $name"

# download stage3 if not already done
#
b=$(basename $stage3)
f=/var/tmp/distfiles/$b
if [[ ! -f $f ]]; then
  wget --quiet $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=/var/tmp/distfiles || exit 6
fi
gpg --verify $f.DIGESTS.asc || exit 7

cd $imagedir  || exit 8
mkdir $name   || exit 9
cd $name
tar xjpf $f   || exit 10

# we use "rsync" within chroot images, "git" would pull in too much deps (gitk etc.)
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

cat << EOF > etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no
sync-type = rsync
sync-uri  = rsync://rsync.de.gentoo.org/gentoo-portage/
EOF

cat << EOF > etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
auto-sync = no
EOF

# change make.conf
#
m=etc/portage/make.conf
chmod a+w $m

sed -i  -e 's/^CFLAGS="/CFLAGS="-march=native /'    \
        -e 's/^USE=/#USE=/'                         \
        -e 's#^DISTDIR=.*#DISTDIR="/var/tmp/distfiles"#' $m

#----------------------------------------
cat << EOF >> $m
USE="
  mmx sse sse2
  pax_kernel xtpax -cdinstall -oci8 -bindist

$(echo $flags | xargs -s 78 | sed 's/^/  /g')
"

$( [[ "$mask" = "unstable" ]] && echo 'ACCEPT_KEYWORDS=~amd64' )
CPU_FLAGS_X86="aes avx mmx mmxext popcnt sse sse2 sse3 sse4_1 sse4_2 ssse3"
PAX_MARKINGS="XT"

#CMAKE_MAKEFILE_GENERATOR="ninja"
#RUBY_TARGETS="ruby23"
#PYTHON_TARGETS="python2_7 python3_4 python3_5"

LINGUAS="en en_GB"
VIDEO_CARDS="intel i965"
SSL_BITS=4096
ACCEPT_LICENSE="*"
CLEAN_DELAY=0
MAKEOPTS="-j1"

EMERGE_DEFAULT_OPTS="--verbose-conflicts --color=n --nospinner --tree --quiet-build --accept-properties=-interactive --accept-restrict=-fetch"

# no "fail-clean", it would delete files before we could pick up them
#
FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox"

PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa warn error"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"

EOF
#----------------------------------------

echo "$mask"        > tmp/MASK

# create portage dirs and symlinks to ../../../tmp/tb/data/
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
  touch etc/portage/$d/zzz                                          # honeypot for autounmask
done
touch       etc/portage/package.mask/self             # avoid a 2nd attempt at this image for failed packages
chmod a+rw  etc/portage/package.mask/self

cat << EOF > etc/portage/env/test
FEATURES="test test-fail-continue"
EOF

cat << EOF > etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CFLAGS"
FEATURES="splitdebug"
EOF

cp -L /etc/hosts /etc/resolv.conf etc/

mkdir       tmp/tb

cat << EOF > root/.vimrc
set softtabstop=2
set shiftwidth=2
set tabstop=2

:let g:session_autosave = 'no'
EOF

# keep nano even if another editor is emerged too
#
echo "app-editors/nano" >> var/lib/portage/world

pks=tmp/packages
touch $pks
chown tinderbox.tinderbox $pks

# test all packages of the portage tree in a randomized order
# the INFO line prevents insert_pkgs.sh to feed this image before the setup is finished
#
qsearch --all --nocolor --name-only --quiet 2>/dev/null | sort --random-sort > $pks
echo "INFO start working on the package list" >> $pks

# tweaks requested by devs
#
# set XDG_CACHE_HOME=/tmp/xdg in job.sh: https://bugs.gentoo.org/show_bug.cgi?id=567192
#
mkdir tmp/xdg
chmod 700 tmp/xdg
chown tinderbox:tinderbox tmp/xdg

# basic package installation of the chroot image
#
#----------------------------------------
cat << EOF > tmp/setup.sh

eselect profile set $profile            || exit 3

echo "en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
. /etc/profile

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data
emerge --noreplace net-misc/netifrc

emerge sys-apps/elfix || exit 4
migrate-pax -m

eselect news read >/dev/null

emerge mail-mta/ssmtp mail-client/mailx || exit 6
echo "
root=tinderbox@zwiebeltoralf.de
MinUserId=9999
mailhub=zwiebeltoralf.de:465
rewriteDomain=your-server.de
hostname=www325.your-server.de
UseTLS=YES
Debug=NO
" > /etc/ssmtp/ssmtp.conf || exit 7

# sharutils provides "uudecode", gentoolkit has "equery" and "eshowkw", portage-utils has "qlop"
#
emerge app-arch/sharutils app-portage/gentoolkit app-portage/pfl app-portage/portage-utils sys-kernel/hardened-sources || exit 8

# try to automatically tweak USE flag in that manner that at least the very first @world upgrade might succeed
#
emerge --deep --update --newuse --changed-use --with-bdeps=y @world --pretend &> /tmp/world.log
if [[ \$? -ne 0 ]]; then
  grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/world.log | grep "^>=" > /etc/portage/package.use/world
  if [[ \$? -eq 0 ]]; then
    echo
    echo "changed USE flags :"
    cat /etc/portage/package.use/world
    echo
    emerge --deep --update --newuse --changed-use --with-bdeps=y @world --pretend &> /tmp/world.log
    if [[ \$? -ne 0 ]]; then
      exit 9
    fi
  else
    exit 10
  fi
fi

exit 0

EOF
#----------------------------------------

cd - 1>/dev/null

$(dirname $0)/chr.sh $name '/bin/bash /tmp/setup.sh'
rc=$?

if [[ $rc -ne 0 ]]; then
  echo
  echo "-------------------------------------"

  if [[ -f $name/tmp/world.log ]]; then
    echo
    cat $name/tmp/world.log
  fi

  echo
  echo " setup NOT successful (rc=$rc) @ $name"
  echo
  echo "-------------------------------------"

  exit $rc
fi

# create symlink to $HOME if the setup was successful
#
p=$(basename $(pwd))
cd $tbhome
ln -s $p/$name || exit 11

echo
echo " setup done: $name"
echo

if [[ "$autostart" = "y" ]]; then
  echo " starting the image: $name"
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
