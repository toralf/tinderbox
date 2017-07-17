#!/bin/sh
#
# set -x

# switch a tinderbox image from OpenSSL to LibeSSL
# inspired by https://wiki.gentoo.org/wiki/Project:LibreSSL
#

pks="/tmp/packages"

echo
echo "=================================================================="
echo

if [[ ! -e $pks ]]; then
  echo " don't run this script outside of a tinderbox image !"
  exit 21
fi

# define the SSL vendor in make.conf
#
cat << EOF >> /etc/portage/make.conf
CURL_SSL="libressl"
USE="\${USE} -openssl -gnutls libressl"
EOF

# mask OpenSSL forever
#
echo "dev-libs/openssl" > /etc/portage/package.mask/openssl

mkdir -p /etc/portage/profile

# unmask LibreSSL related USE flags
#
cat << EOF >> /etc/portage/profile/use.stable.mask
-libressl
-curl_ssl_libressl
EOF

# switch to LibeSSL often fails w/o these settings
#
cat << EOF > /etc/portage/package.use/libressl
dev-db/mysql-connector-c  -ssl
dev-lang/python           -tk
dev-qt/qtsql              -mysql
dev-qt/qtnetwork          -ssl
EOF

# few unstable packages need being keyworded too at a stable image
#
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -eq 1 ]]; then
  cat << EOF > /etc/portage/package.accept_keywords/libressl
dev-libs/libressl
~mail-mta/ssmtp-2.64-r3
EOF
fi

# fetch packages before openssl will be uninstalled
# (wget won't work before it is been rebuild against libressl)
#
emerge -f dev-libs/libressl net-misc/openssh mail-mta/ssmtp net-misc/wget dev-lang/python || exit 28

# unmerge of OpenSSL should already schedule a @preserved-rebuild in the script job.sh
# but force it here too with "%" to definitely bail out if it fails
#
cat << EOF >> $pks
%emerge @preserved-rebuild
%emerge -C openssl
EOF

exit 0
