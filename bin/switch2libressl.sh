#!/bin/sh
#
# set -x

sed -i  -e 's/ [+-]*openssl/[ ]*/g'   \
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
