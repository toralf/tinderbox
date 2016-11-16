#!/bin/sh
#
# set -x

# https://wiki.gentoo.org/wiki/Project:LibreSSL

sep="=================================================================="
echo -e "\n$sep\n$0: start"

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

mkdir -p /etc/portage/profile

cat << EOF >> /etc/portage/profile/use.stable.mask
-libressl
-curl_ssl_libressl

EOF

echo "dev-libs/openssl"   >  /etc/portage/package.mask/openssl

cat << EOF > /etc/portage/package.use/libressl
dev-db/mysql-connector-c  -ssl
dev-lang/python           -tk
dev-qt/qtsql              -mysql

EOF

py2="dev-lang/python:2.7"
py3="dev-lang/python:3.4"

# keyword packages at a *stable* image
#
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -ne 0 ]]; then
  cat << EOF > /etc/portage/package.accept_keywords/libressl || exit 23
dev-libs/libressl
$py2
$py3
~app-eselect/eselect-python-20160516
~dev-lang/python-exec-2.4.3

~dev-libs/libevent-2.1.5
~mail-mta/ssmtp-2.64
~net-nds/openldap-2.4.44
~www-client/lynx-2.8.9_pre9

EOF

fi

echo -e "\n$sep\n$0: fetch"

# fetch packages before we uninstall openssl and break therefore wget
#
emerge -f libressl openssh wget python || exit 24

echo -e "\n$sep\n$0: unmerge"

qlist --installed --nocolor dev-libs/openssl
if [[ $? -eq 0 ]]; then
  emerge -C openssl || exit 25
fi

echo -e "\n$sep\n$0: re-merge"

emerge -1 libressl        &&\
emerge -1 openssh         &&\
emerge -1 wget            &&\
emerge -1 $py2 $py3       &&\
emerge @preserved-rebuild &&\
emerge -u --changed-use mail-mta/ssmtp
rc=$?

echo -e "\n$sep\n$0: rc=$rc"

exit $rc
