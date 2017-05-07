#!/bin/sh
#
# set -x

# setup a new tinderbox image
#
# typical call:
#
# $> echo "cd ~/img2; sudo /opt/tb/bin/tbs.sh" | at now + 0 min

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
    ldap libinput libkms libnotify libvirtd llvm logrotate lua luajit lvm lzma mad
    mbox mdnsresponder-compat melt midi mikmod minimal minizip mng mod
    modplug mono mp3 mp4 mpeg mpeg2 mpeg3 mpg123 mpi mssql mta mtp multimedia
    mysql mysqli natspec ncurses networking nscd nss obj objc odbc
    offensive ogg ois opencv openexr opengl openmpi openssl opus osc pam
    pcre16 perl php pkcs11 plasma plotutils plugins png policykit postgres
    postproc postscript printsupport pulseaudio pwquality pypy python qemu
    qml qt5 rdoc rdp rendering ruby sasl scripts scrypt sddm sdl secure-delete
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
    if [[ "$libressl" = "y"  && "$f" = "gnutls" ]]; then
      echo -n " -$f"
      continue
    fi

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
  b="$(basename $profile)"

  if [[ "$b" = "no-multilib" || "$b" = "systemd" ]]; then
    name="$(basename $(dirname $profile))-$b"
    stage3=$(grep "^20....../$b/stage3-amd64-$b-20.......tar.bz2" $latest | cut -f1 -d' ')

  else
    name="$b"
    stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $latest | cut -f1 -d' ')
  fi

  # don't mention the default (unstable)
  #
  if [[ "$keyword" = "stable" ]]; then
    name="$name-$keyword"
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
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  f=$distfiles/$(basename $stage3)
  if [[ ! -f $f || ! -s $f ]]; then
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

  mkdir $name || exit 4
  cd $name    || exit 4
  tar -xjpf $f --xattrs --exclude='./dev/*' || exit 4
}


# configure our 3 repositories and prepare 1 placeholder too
# the local repository rules always
#
function CompileRepoFiles()  {
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
          etc/portage/make.conf

  # tinderbox needs to be in group "portage" for edit perms
  #
  chgrp portage etc/portage/make.conf
  chmod g+w etc/portage/make.conf

  if [[ -n "$origin" ]]; then
    l10n=$(grep "^L10N" $origin/etc/portage/make.conf | cut -f2- -d'=')
  else
    l10n="$(grep -v -e '^$' -e '^#' /usr/portage/profiles/desc/l10n.desc | cut -f1 -d' ' | sort --random-sort | head -n $(($RANDOM % 10)) | sort | xargs)"
  fi

  cat << EOF >> etc/portage/make.conf
CFLAGS="-O2 -pipe -march=native -Wall"
CXXFLAGS="-O2 -pipe -march=native"

USE="
  ssp -bindist -cdinstall -oci8

$( echo $flags | xargs -s 78 | sed 's/^/  /g' )
"

ACCEPT_KEYWORDS=$( [[ "$keyword" = "unstable" ]] && echo '~amd64' || echo 'amd64' )

ACCEPT_LICENSE="*"

MAKEOPTS="-j1"
NINJAFLAGS="-j1"

EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --color=n --nospinner --tree --quiet-build --with-bdeps=y"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"
CLEAN_DELAY=0

ALSA_CARDS="hda-intel"
INPUT_DEVICES="evdev libinput"
VIDEO_CARDS="intel i965"

L10N="$l10n"

FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox -news"

DISTDIR="$distfiles"
PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"
EOF
}


# symlink the (host shared) package files from
# the local /tmp/tb/data to the local portage directories
#
function CompilePackageFiles()  {
  mkdir tmp/tb  # mount point for the tinderbox directory of the host

  # create portage directories and symlinks
  #
  mkdir usr/portage
  mkdir var/tmp/{distfiles,portage}

  for d in package.{accept_keywords,env,mask,unmask,use} env profile
  do
    [[ ! -d etc/portage/$d ]] && mkdir etc/portage/$d
    chmod 777 etc/portage/$d
  done

  (cd etc/portage; ln -s ../../../tmp/tb/data/patches)

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

  touch      etc/portage/package.use/setup     # USE flags added during setup phase
  chmod a+rw etc/portage/package.use/setup

  # activate at every n-th image predefined USE flag sets
  #
  if [[ $(($RANDOM % 100)) -lt 40 ]]; then
    (cd etc/portage/package.use; ln -s ../../../tmp/tb/data/package.use.ff-and-tb ff-and-tb)
  fi

  if [[ $(($RANDOM % 100)) -lt 25 ]]; then
    (cd etc/portage/package.use; ln -s ../../../tmp/tb/data/package.use.ffmpeg ffmpeg)
  fi

  echo "*/* $(cpuid2cpuflags)" > etc/portage/package.use/00cpuflags

  if [[ "$(basename $profile)" = "systemd" ]]; then
    echo "sys-apps/util-linux -udev" >> etc/portage/package.use/util-linux
  fi

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

  # breakage with XDG_* settings in job.sh is forced
  #
  echo 'FEATURES="-sandbox -usersandbox"'   > etc/portage/env/nosandbox

  # test known to be broken
  #
  echo 'FEATURES="test-fail-continue"'      > etc/portage/env/test-fail-continue
}


# DNS resolution + .vimrc (avoid interactive question)
#
function CompileMiscFiles()  {
  cp -L /etc/hosts /etc/resolv.conf etc/

  cat << EOF > root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0
EOF
}


# the last line int the file is the first task
#
function FillPackageList()  {
  pks=tmp/packages

  # in favour of a good coverage do not test repo changes at all images
  #
  if [[ $(($RANDOM % 3)) -eq 0 ]]; then
    echo '# this keeps insert_pkgs.sh away' > $pks
  fi

  # fill up the randomized package list
  #
  qsearch --all --nocolor --name-only --quiet | sort --random-sort >> $pks

  if [[ -n "$origin" ]]; then
    # replay the emerge history of origin before we continue with the randomized list
    #
    qlop --nocolor --list -f $origin/var/log/emerge.log 2>/dev/null | awk ' { print $7 } ' | xargs qatom | cut -f1-2 -d' ' | tr ' ' '/' > $pks.origin
    echo "INFO $(wc -l < $pks.tmp) packages of $origin replayed" >> $pks
    tac $pks.origin >> $pks
    rm $pks.origin
  fi

  # emerge/upgrade mandatory package/s and upgrade @system
  # "# ..." keeps insert_pks.sh away till the basic image setup is done
  #
  cat << EOF >> $pks
# setup done
@world
app-text/wgetpaste
app-portage/pfl
app-portage/eix
@system
%rm -f /etc/portage/package.mask/setup_blocker
EOF

  # switch to another SSL vendor before @system upgrade is made
  #
  if [[ "$libressl" = "y" ]]; then
    echo "%/tmp/switch2libressl.sh" >> $pks
  fi

  # "%" is needed here b/c "sys-kernel/*" is in IGNORE_PACKAGE
  #
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    echo "%emerge -u sys-kernel/vanilla-sources"  >> $pks
  else
    echo "%emerge -u sys-kernel/gentoo-sources"   >> $pks
  fi

  # GCC first
  #
  echo "%emerge -u sys-devel/gcc" >> $pks

  chmod a+w $pks
}


# repos.d/* , make.conf and all the stuff
#
function ConfigureImage()  {
  mkdir -p                  usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > usr/local/portage/metadata/layout.conf
  echo 'local' >            usr/local/portage/profiles/repo_name
  chown -R portage:portage  usr/local/portage/
  chmod g+s                 usr/local/portage/

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
# - dry test of GCC
# - dry test of @system upgrade as an attempt to auto-fix package-specific USE flags deps
#
function CreateSetupScript()  {
  dryrun="emerge --backtrack=100 --deep --update --changed-use @system --pretend"
  perl_stable_version=$(portageq best_version / dev-lang/perl)

  cat << EOF > tmp/setup.sh
#!/bin/sh
#
#set -x

# this file is automatically generated by $(basename $0)

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

# newer available unstable Perl versions often prevents basic setup, GCC upgrade or LibreSSL switch
#
echo ">${perl_stable_version}" > /etc/portage/package.mask/setup_blocker

emerge sys-apps/elfix || ExitOnError 6

emerge mail-mta/ssmtp || ExitOnError 7
emerge mail-client/mailx || ExitOnError 7
(cd /etc/ssmtp && ln -snf ../../tmp/tb/sdata/ssmtp.conf) || ExitOnError 7

emerge app-arch/sharutils app-portage/gentoolkit app-portage/portage-utils www-client/pybugz || ExitOnError 8
(cd /root && ln -snf ../tmp/tb/sdata/.bugzrc) || ExitOnError 8

emerge -u sys-apps/sandbox || ExitOnError 8

\$( [[ "$multilib" = "y" ]] && echo 'ABI_X86="32 64"' >> /etc/portage/make.conf )

emerge --update --pretend sys-devel/gcc || exit 9

mv /etc/portage/package.mask/setup_blocker /tmp/
for i in 1 2 3
do
  $dryrun &> /tmp/dryrun.log
  if [[ \$? -eq 0 ]]; then
    rc=0
    break
  fi

  if [[ \$i -lt 3 ]]; then
    grep -A 1000 'The following USE changes are necessary to proceed:' /tmp/dryrun.log | grep '^>=' | sort -u >> /etc/portage/package.use/setup
  else
    rc=9
  fi
done
mv /tmp/setup_blocker /etc/portage/package.mask/

exit \$rc
EOF
}


# at least a working mailer and bugz are needed
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
    echo "    sudo $(dirname $0)/chr.sh $mnt '  $dryrun  '"
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
if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# the distfiles directory at the host, shared to all images
#
distfiles=/var/tmp/distfiles

# the remote stage3 location
#
wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
wgetpath=/releases/amd64/autobuilds

autostart="y"   # start the image after setup ?
origin=""       # clone from another image ?
suffix=""       # will be appended onto the name before the timestamp

# set defaults for profile, keyword, ssl vendor and ABI_X86
#
profile=$(eselect profile list | awk ' { print $2 } ' | grep "^default" | grep -v -e '/x32' -e "/developer" -e "/uclibc" -e "/selinux" | sort --random-sort | head -n1)

keyword="unstable"

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  libressl="y"
else
  libressl="n"
fi

if [[ "$keyword" = "stable" ]]; then
  libressl="n"
fi

multilib="n"
echo "$profile" | grep -q 'no-multilib'
if [[ $? -ne 0 ]]; then
  if [[ $(($RANDOM % 4)) -eq 0 ]]; then
    multilib="y"
  fi
fi

flags=$(rufs)   # default is an arbitrary USE flag subset

# the caller can overwrite the (thrown) settings now
#
while getopts a:f:k:l:m:o:p:s: opt
do
  case $opt in
    a)  autostart="$OPTARG"
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
          flags="$(echo $flags | xargs -n 1 | grep -v -e 'openssl' -e 'libressl' -e 'gnutls' | xargs)"
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
if [[ "/home/tinderbox" = "$(pwd)" ]]; then
  echo "you are in /home/tinderbox !"
  exit 3
fi

latest=$distfiles/latest-stage3.txt
wget --quiet $wgethost/$wgetpath/latest-stage3.txt --output-document=$latest || exit 3

ComputeImageName
mnt=$(pwd | sed 's,/home/tinderbox/,,g')/$name
echo " $mnt"
echo
UnpackStage3
ConfigureImage
EmergeMandatoryPackages

cd /home/tinderbox/run && ln -s ../$mnt || exit 11

echo
echo " setup  OK: $name"
echo

if [[ "$autostart" = "y" ]]; then
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
fi

exit 0
