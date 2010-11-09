#!/bin/bash
#
# This software is copyright (c) 2006-2010 by Al Tobey.
#
# This is free software; you can redistribute it and/or modify it under the terms
# of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
# version 2.0 is GPL compatible by itself, hence there is no benefit to having an
# Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.
#
# This program will expand /boot/initrd.cpio.gz into /tmp/test and chroot into it.
# Pretty much unmodified since 2006.
#
# The directory is cleaned up on shell exit.
# TODO: make this safer, maybe use mktemp and/or a tmpfs mount

mkdir -p /tmp/test
cd /tmp/test

if [ -x unmount ] ; then
	./unmount
fi

umount ./dev 2>/dev/null
umount ./sys 2>/dev/null
umount ./proc 2>/dev/null
umount ./realroot 2>/dev/null

for i in `grep '/tmp/test' /proc/mounts`
do
	mnt=`echo $i |awk '{print $1}'`
	umount $mnt
	if [ $? -ne 0 ] ; then
		echo "Failed to unmount $i ... bailing out."
		exit 1
	fi
done

echo "##############################################"
cat /proc/mounts
echo "##############################################"
echo "Make sure no realroots are mounted or anything stupid like that then"
echo "press ENTER to continue (Ctrl-C to quit)."
read BUFFOON

rm -rf /tmp/test/*

gunzip -c /boot/initrd.cpio.gz |cpio -ivdm

SHELL=/bin/sh exec chroot /tmp/test

