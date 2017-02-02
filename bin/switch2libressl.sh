#!/bin/sh
#
# set -x

# https://wiki.gentoo.org/wiki/Project:LibreSSL

pks="/tmp/packages"

echo
echo "=================================================================="
echo

# are we within a tinderbox chroot image ?
#
if [[ ! -e $pks ]]; then
  echo " we're not within a tinderbox image"
  exit 21
fi

# change make.conf and other portage config files
#
sed -i  -e '/^CURL_SSL="/d'           \
        -e 's/ [+-]*openssl[ ]*/ /'   \
        -e 's/ [+-]*libressl[ ]*/ /'  \
        -e 's/ [+-]*gnutls[ ]*/ /'    \
        -e 's/USE="/CURL_SSL="libressl"\nUSE="-openssl -gnutls libressl \n  /' \
        /etc/portage/make.conf || exit 22

mkdir -p /etc/portage/profile || exit 23

# mask openssl
#
echo "dev-libs/openssl" > /etc/portage/package.mask/openssl || exit 24

# unmask libressl USSE flags
#
cat << EOF >> /etc/portage/profile/use.stable.mask || exit 25
-libressl
-curl_ssl_libressl
EOF

# libressl switch often fails w/o these USE flags
#
cat << EOF > /etc/portage/package.use/libressl || exit 26
dev-db/mysql-connector-c  -ssl
#dev-lang/python           -tk
dev-qt/qtsql              -mysql
EOF

py2="dev-lang/python:2.7"
py3="dev-lang/python:3.4"

# keyword certain packages at a *stable* image
#
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -eq 1 ]]; then
  cat << EOF > /etc/portage/package.accept_keywords/libressl || exit 27
dev-libs/libressl
$py2
$py3
~dev-libs/libevent-2.1.8
~mail-mta/ssmtp-2.64
~www-client/lynx-2.8.9_pre11
EOF
fi

# fetch packages before openssl is uninstalled
# (b/c wget won't work after uninstalling openssl)
#
emerge -f libressl openssh wget python || exit 28

# we use "%<cmd>" here to force Finish() in the case of an emerge failure
#
cat << EOF >> $pks || exit 29
# entries by $0 at $(date)
%emerge -u --changed-use mail-mta/ssmtp
%emerge @preserved-rebuild
%emerge -1 $py2 $py3
%emerge -1 wget
%emerge -1 openssh
%emerge -1 libressl
%emerge -C openssl
EOF

exit 0
