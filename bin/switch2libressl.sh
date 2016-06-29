#!/bin/sh
#
# set -x

sed -i -e 's/ [+-]*openssl/[ ]*/g' -e 's/ [+-]*libressl[ ]*/ /' /etc/portage/make.conf
sed -i -e 's/USE="/USE="-openssl libressl/'                     /etc/portage/make.conf
echo '"CURL_SSL="-openssl libressl"'                         >> /etc/portage/make.conf

mkdir -p /etc/portage/profile
echo "-libressl"          >> /etc/portage/profile/use.stable.mask

echo "dev-libs/openssl"   >> /etc/portage/package.mask/openssl
echo "dev-libs/libressl"  >> /etc/portage/package.accept_keywords/libressl

echo "=dev-lang/python-2.7.11-r2"           >> /etc/portage/package.accept_keywords/libressl
echo "=dev-lang/python-3.4.3-r7"            >> /etc/portage/package.accept_keywords/libressl
echo "=app-eselect/eselect-python-20160222" >> /etc/portage/package.accept_keywords/libressl
echo "=dev-lang/python-exec-2.4.3"          >> /etc/portage/package.accept_keywords/libressl
echo "=net-misc/iputils-20121221-r2"        >> /etc/portage/package.accept_keywords/libressl

echo "dev-libs/libevent"                    >> /etc/portage/package.accept_keywords/libressl
echo "dev-lang/erlang"                      >> /etc/portage/package.accept_keywords/libressl

emerge -f libressl  &&\
emerge -C openssl   &&\
emerge -1 libressl  &&\
emerge -1 openssh   &&\
emerge -1 wget      &&\

emerge -1 =dev-lang/python-2.7.11-r2 =dev-lang/python-3.4.3-r7  &&\
emerge -1 =net-misc/iputils-20121221-r2                         &&\
emerge @preserved-rebuild

exit $?
