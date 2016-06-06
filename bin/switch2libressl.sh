#!/bin/sh
#
#set -x

echo 'USE="${USE} libressl"'  >> /etc/portage/make.conf
mkdir -p /etc/portage/profile
echo "-libressl"              >> /etc/portage/profile/use.stable.mask
echo "dev-libs/openssl"       >> /etc/portage/package.mask/openssl
echo "dev-libs/libressl"      >> /etc/portage/package.accept_keywords/libressl

emerge -f   libressl 
emerge -C   openssl 
emerge -1q  libressl
emerge -1q  openssh
emerge -1q  wget

echo "=dev-lang/python-2.7.11-r2"           >> /etc/portage/package.accept_keywords/libressl
echo "=dev-lang/python-3.4.3-r7"            >> /etc/portage/package.accept_keywords/libressl
echo "=app-eselect/eselect-python-20160222" >> /etc/portage/package.accept_keywords/libressl
echo "=dev-lang/python-exec-2.4.3"          >> /etc/portage/package.accept_keywords/libressl
echo "=net-misc/iputils-20121221-r2"        >> /etc/portage/package.accept_keywords/libressl

emerge -1q =dev-lang/python-2.7.11-r2 =dev-lang/python-3.4.3-r7
emerge -1q =net-misc/iputils-20121221-r2
emerge -q @preserved-rebuild
