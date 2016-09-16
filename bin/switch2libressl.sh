#!/bin/sh
#
# set -x

# https://wiki.gentoo.org/wiki/Project:LibreSSL

# are we within a tinderbox chroot image ?
#
if [[ ! -e /tmp/packages || ! -e /tmp/setup.sh || ! -e /tmp/setup.log ]]; then
  echo " we're not within a tinderbox image"
  if [[ "$1" = "-f" ]]; then
    echo -en "\n and you forced us to continue ! "
    for i in $(seq 1 10); do
      echo -n '.'
      sleep 1
    done
    echo ' going on'
  else
    exit 21
  fi
fi

# change make.conf and other portage config files
#
sed -i  -e '/^CURL_SSL="/d'           \
        -e 's/ [+-]*openssl[ ]*/ /'   \
        -e 's/ [+-]*libressl[ ]*/ /'  \
        -e 's/ [+-]*gnutls[ ]*/ /'    \
        -e 's/USE="/CURL_SSL="libressl"\nUSE="-openssl -gnutls libressl \n  /' \
        /etc/portage/make.conf

mkdir -p                      /etc/portage/profile
echo "-libressl"          >>  /etc/portage/profile/use.stable.mask
echo "-curl_ssl_libressl" >>  /etc/portage/profile/use.stable.mask

echo "dev-libs/openssl"   >   /etc/portage/package.mask/openssl || exit 22

py2="dev-lang/python:2.7"
py3="dev-lang/python:3.4"

# keyword at a stable image appropriate packages
#
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -ne 0 ]]; then
  cat << EOF > /etc/portage/package.accept_keywords/libressl || exit 23
dev-libs/libressl
$py2
$py3
=app-eselect/eselect-python-20160222
=dev-lang/python-exec-2.4.3
dev-libs/libevent

~mail-mta/ssmtp-2.64
~net-analyzer/tcpdump-4.7.4
~dev-python/cryptography-1.3.4
~www-client/lynx-2.8.9_pre9
EOF

fi

# fetch packages before we uninstall any package
#
emerge -f libressl openssh wget python iputils || exit 24

qlist -IC dev-libs/openssl
if [[ $? -eq 0 ]]; then
  emerge -C openssl || exit 25
fi

emerge -1 libressl        &&\
emerge -1 openssh         &&\
emerge -1 wget            &&\
emerge -1 $py2 $py3       &&\
emerge @preserved-rebuild
rc=$?

if [[ $rc -ne 0 ]]; then
  exit 26
fi

rm /etc/portage/package.mask/openssl
exit 0
