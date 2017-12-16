#!/bin/sh
#
# set -x

# switch a tinderbox image from OpenSSL to LibreSSL
# inspired by https://wiki.gentoo.org/wiki/Project:LibreSSL

backlog="/tmp/backlog"

echo
echo "=================================================================="
echo

if [[ ! -e $backlog ]]; then
  echo " don't run this script outside of a tinderbox image !"
  exit 1
fi

# configure the SSL vendor in global USE flags
#
cat << EOF >> /etc/portage/make.conf
CURL_SSL="libressl"
USE="\${USE} libressl -gnutls -openssl"
EOF

# mask OpenSSL package
#
echo "dev-libs/openssl" > /etc/portage/package.mask/openssl

# quirks for an easier image setup
#
cat << EOF > /etc/portage/package.use/libressl
net-misc/iputils          -ssl
sys-auth/polkit           -kde
EOF
chmod a+rw /etc/portage/package.use/libressl

# unstable package(s) needed at stable
#
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -eq 1 ]]; then
  cat << EOF > /etc/portage/package.accept_keywords/libressl
EOF
fi

# unmerge of OpenSSL triggers a @preserved-rebuild
# and job.sh usually exits if it fails;
# but use "%" here to definitely bail out
#
cat << EOF >> $backlog.1st
%emerge @preserved-rebuild
%emerge -C openssl
EOF

# fetch before OpenSSL is uninstalled
# b/c then fetch command itself wouldn't work until being rebuild against LibreSSL
#
emerge -f dev-libs/libressl net-misc/openssh mail-mta/ssmtp net-misc/wget dev-lang/python
exit $?
