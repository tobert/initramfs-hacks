#!/bin/bash
#
# This software is copyright (c) 2006-2010 by Al Tobey.
#
# This is free software; you can redistribute it and/or modify it under the terms
# of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
# version 2.0 is GPL compatible by itself, hence there is no benefit to having an
# Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.
#
# This script assembles an initramfs on the fly and boots into it with
# KVM to verify scripting functionality.
# Chances are it won't tell you much about if your gear is supported
# unless your gear is KVM.
#
# requires a static kernel in the same directory as this script as "vmlinuz"
# also assumed to be in the same directory as make-initramfs.sh

bindir=`dirname $0`
INITRAMFS=`tempfile`
DISK=`tempfile`
DATA=`tempfile`
MAC0="00:16:3e:00:00:01"
MAC1="00:16:3e:00:00:02"

bash "$bindir/make_initramfs.sh" $INITRAMFS

if [ $? -ne 0 ] ; then
	echo fail
	exit 1
fi

# create two sparse files, one "root" disk and one "data" disk
# The files will consume no more space than an inode at creation and likely
# never consume any as long as they're not written to.
# These disks are quite handy for testing automatic partitioning in init
# scripts if using variants of these scripts for system imaging.
dd if=/dev/zero of=$DISK bs=1k count=0 seek=8388608    # 2^33 / 1024: 4G
dd if=/dev/zero of=$DATA bs=1k count=0 seek=1073741824 # 2^40 / 1024: 512G

kvm -drive file=$DISK,if=virtio,index=0,boot=on \
    -drive file=$DATA,if=scsi \
    -kernel $bindir/vmlinuz \
    -initrd $INITRAMFS \
    -append "panic=30" \
    -net tap,script=$bindir/kvm-ifup-br0,vlan=0 \
    -net tap,script=$bindir/kvm-ifup-br0,vlan=1 \
    -net nic,model=virtio,vlan=0,macaddr=$MAC0 \
    -net nic,model=virtio,vlan=1,macaddr=$MAC1 \
    -m 512m \
    -name "initramfs_test" \
    -curses \
    -no-reboot

    # most servers have two nics and many of my scripts support dual nics
    # so always boot two nics even if one of the bridges isn't DHCP enabled
    # depending on your kernel you might want to switch virtio to e1000

    # newer/el5 style ...
    #-net nic,vlan=0,model=virtio,macaddr=$MAC0,name=eth0 \
    #-net nic,vlan=1,model=virtio,macaddr=$MAC1,name=eth1 \
    #-net tap,vlan=0,name=hostnet0,script=$bindir/kvm-ifup-br0,downscript=$bindir/kvm-ifdown-br0 \
    #-net tap,vlan=1,name=hostnet1,script=$bindir/kvm-ifup-br1,downscript=$bindir/kvm-ifdown-br1 \

rm -f $INITRAMFS
rm -f $DISK

