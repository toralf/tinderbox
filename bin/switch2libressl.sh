#!/bin/sh
#
# set -x

# https://wiki.gentoo.org/wiki/Project:LibreSSL

pks="/tmp/packages"

echo
echo "=================================================================="
echo

# test to be within a tinderbox chroot image ?
#
if [[ ! -e $pks ]]; then
  echo " don't run this script outside of a tinderbox image !"
  exit 21
fi

# set libressl as the preferred vendor in change make.conf:
#
# CURL_SSL="libressl"
# USE="-openssl -gnutls libressl
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

# unmask libressl related USE flags
#
cat << EOF >> /etc/portage/profile/use.stable.mask || exit 25
-libressl
-curl_ssl_libressl
EOF

# libressl switch often fails w/o these settings
#
cat << EOF > /etc/portage/package.use/libressl || exit 26
dev-db/mysql-connector-c  -ssl
dev-lang/python           -tk
dev-qt/qtsql              -mysql
EOF


# at a stable image certain packages needs keywording
#
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -eq 1 ]]; then
  cat << EOF > /etc/portage/package.accept_keywords/libressl || exit 27
dev-libs/libressl
dev-lang/python:2.7
dev-lang/python:3.4
~dev-libs/libevent-2.1.8
~mail-mta/ssmtp-2.64
~www-client/lynx-2.8.9_pre11
EOF
fi

# fetch packages before openssl is uninstalled
# (and therefore wget wouldn't work before been rebuild)
#
emerge -f dev-libs/libressl net-misc/openssh mail-mta/ssmtp net-misc/wget dev-lang/python || exit 28

# unmerge of opensll should in PostEmerge() schedules a @preserved-rebuild
# but force it again with "%" to bail out if it fails
#
cat << EOF >> $pks
%emerge @preserved-rebuild
%emerge -C openssl
EOF

exit 0
