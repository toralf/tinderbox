#!/bin/sh
#
# set -x

# switch from OpenSSL to LibreSSL

# typical call:
#
# sudo ~/tb/bin/chr.sh amd64-hardened-unstable-libressl_20160821-203105 "/tmp/tb/bin/switch2libressl.sh"

# are we within a tinderbox chroot image ?
#
if [[ ! -e /tmp/packages || ! -e /tmp/setup.sh || ! -e /tmp/setup.log ]]; then
  echo " we're not within a tinderbox image"
  if [[ "$1" = "-f" ]]; then
    echo -en "\n and you forced us to continue ! "
    for i in $(seq 1 10); do
      echo -n '.'
    fi
    echo ' going on'
  else
    exit 1
  fi
fi

sed -i  -e 's/ [+-]*openssl[ ]*/ /'   \
        -e 's/ [+-]*libressl[ ]*/ /'  \
        -e 's/ [+-]*gnutls[ ]*/ /'    \
        -e 's/USE="/CURL_SSL="libressl"\nUSE="-openssl -gnutls libressl \n  /' \
        /etc/portage/make.conf

mkdir -p /etc/portage/profile
echo "-libressl"          > /etc/portage/profile/use.stable.mask

echo "dev-libs/openssl"   > /etc/portage/package.mask/openssl
echo "dev-libs/libressl"  > /etc/portage/package.accept_keywords/libressl

cat << EOF > /etc/portage/package.accept_keywords/libressl
=dev-lang/python-2.7.11-r2
=dev-lang/python-3.4.3-r7
=app-eselect/eselect-python-20160222
=dev-lang/python-exec-2.4.3
=net-misc/iputils-20121221-r2

dev-libs/libevent
dev-lang/erlang
EOF

emerge -f libressl  &&\
emerge -C openssl   &&\
emerge -1 libressl  &&\
emerge -1 openssh   &&\
emerge -1 wget      &&\

emerge -1 =dev-lang/python-2.7.11-r2 =dev-lang/python-3.4.3-r7  &&\
emerge -1 =net-misc/iputils-20121221-r2                         &&\
emerge @preserved-rebuild

exit $?
