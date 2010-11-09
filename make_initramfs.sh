#!/bin/bash
#
# This software is copyright (c) 2006-2010 by Al Tobey.
#
# This is free software; you can redistribute it and/or modify it under the terms
# of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
# version 2.0 is GPL compatible by itself, hence there is no benefit to having an
# Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.
#
# This generates a system-specific initramfs with support for LVM2 and ATA.  This
# script is mostly unmodified from my original 2006 version except for cleaning
# up a couple of the dumber mistakes I noticed when prepping for this project.
#
# TODO: switch to using functions in initramfs-lib.sh
#bindir=`dirname $0`
#source "$bindir/initramfs-lib.sh"

# list of kernel modules - adjust to your system
modules="dm-mod ata_piix libata scsi_mod sd_mod ext3 jbd"

# directory to use for building the image
# mount tmpfs or another disk/LV here for extra safety from damage to the host system
DIR=/var/tmp/custom-initrd

# where to write the file when it's done
TARGET_FILE=/boot/initrd.cpio.gz
[ -n "$1" ] && TARGET_FILE="$1"

# use ldd(1) to determine all the dynamic libraries a program is
# linked with and copy them into the image
# It works fine for now without being recursive on Ubuntu, but
# may need to grab dependencies on other distros ...
cpdeps () {
	FILE=$1
	DEPS=`ldd $DIR/bin/$FILE |awk -F '=>' '/\/lib\//{print $2}'`
	for i in $DEPS
	do
		if [ -f "$i" -a ! -e $DIR/lib/$i ] ; then
			cp $i "$DIR/lib"
		fi
	done
}

# clean up mounts from testing or lose files
for i in `grep "($DIR|/tmp/test)" /proc/mounts`
do
	mnt=`echo $i |awk '{print $1}'`
	umount $mnt
	if [ $? -ne 0 ] ; then
		echo "Failed to unmount $i ... bailing out."
		exit 1
	fi
done

# one time I had a hanging mount and the rm -rf cleanup ended
# up wiping a bit of my system that I had to restore from
# backup - BE CAREFUL!
echo "##############################################"
cat /proc/mounts
echo "##############################################"
echo "Make sure no realroots are mounted or anything stupid like that then"
echo "press ENTER to continue (Ctrl-C to quit)."
read BUFFOON

# clean up - be extra careful not to cross mounts
rm -rf --one-file-system $DIR

# build up a skeleton
mkdir -p $DIR/bin
mkdir $DIR/realroot
mkdir $DIR/lib
mkdir $DIR/proc
mkdir $DIR/tmp
mkdir $DIR/dev
mkdir -p $DIR/etc/lvm

echo "Copying configuration files ..."
cp /etc/lvm/lvm.conf $DIR/etc/lvm
# fstab.gz is used to find the fs type for root at boot time.
# It's intentionlly NOT named /etc/fstab to prevent confusion.
gzip -c /etc/fstab > $DIR/etc/fstab.gz

cd $DIR
ln -s bin sbin

# the basics
echo "Installing binaries ..."
cp `which busybox`    $DIR/bin
# if you prefer a full bash ... it's big though
#cp `which bash`      $DIR/bin
cp `which depmod`     $DIR/bin
cp `which modprobe`   $DIR/bin
cp `which lsmod`      $DIR/bin
cp `which pivot_root` $DIR/bin

# this may need modification on some distros ...
echo "Getting LVM binary ..."
lvm_ver=`lvmiopversion`
if [ "x$lvm_ver" != "x" ] ; then
    LVM="/lib/lvm-$lvm_ver/lvm"
    cp $LVM $DIR/bin
elif [ -x /sbin/lvm.static ] ; then
    cp /sbin/lvm.static $DIR/bin/lvm
elif [ -x /sbin/lvm ] ; then
    cp /sbin/lvm $DIR/bin/lvm
fi

# Use the cpdeps function to find all the libraries required for
# each binary.
echo "Installing dynamicly linked libraries ..."
# ld-linux.so.2 MUST be available and isn't found by cpdeps
cp /lib/ld-linux.so.2 $DIR/lib
cd $DIR/bin
for i in *
do
	cpdeps $i
done

echo "Stripping binaries to save space ..."
for i in $DIR/bin/* $DIR/lib/*
do
	if [ -f $i ] ; then
		strip $i
	fi
done

# get kernel modules for ALL kernels listed in /lib/modules
for i in $modules
do
	echo "Installing kernel modules for driver $i ..."
	find /lib/modules -name $i.ko |cpio -pdmu $DIR 2>/dev/null
done

# set up busybox symlinks
cd $DIR/bin
for i in ash awk basename cat cp cpio dirname echo env false find grep gunzip gzip head hexdump hostid hostname httpd id ifconfig insmod ls mkdir mknod mount mv printf ps realpath rm rmdir sed sh sync tail tar tee test touch tr true umount uniq vi xargs sleep uname insmod [
do
	if [ ! -e "$i" ] ; then
		ln -s busybox "$i"
	fi
done

# Run depmod for all kernels, then tgz them indiviually.
# The init script will delete unused tarballs before opening up the
# one for the running kernel to save space on the filesystem.
cd $DIR/lib/modules
for i in *
do
	echo "Generating dependencies for kernel $i and compressing ..."
	chroot $DIR depmod -a $i
    # max compression ... gzip is good enough
	tar -cf - $i |gzip -9c > $DIR/$i.tar.gz
	rm -r $DIR/lib/modules/$i
done

# sometimes I throw bash in ... this switches to it automagically
# just uncomment the copy up above
if [ -x "$DIR/bin/bash" ] ; then
	cd $DIR/bin
	rm sh
	ln -s bash sh
fi

# Save the trouble of being smart about devices required for booting and
# just provide them all.
echo "Creating copy of /dev ..."
busybox tar -czf $DIR/devices.tar.gz /dev 2>/dev/null

echo "Generating init script ..."
# This is the top of the /init script in a HEREDOC.
###############################################################################
cat << EOTOP > $DIR/init
#!/bin/sh

export PATH=/bin
export LD_LIBRARY_PATH=/lib

echo "Creating directories, mounting proc, sysfs, and udev."
mkdir -p /sys
mkdir -p /proc
mkdir -p /tmp
mkdir -p /var/lock
mount -n -t sysfs none /sys
mount -n -t proc none /proc
mount -n -t tmpfs -o mode=0755 udev /dev

echo "Creating device files."
tar -xzf /devices.tar.gz -C /
rm -f /devices.tar.gz

KERNEL=\`uname -r\`

# make some more space by clearing out unneeded kernel modules
MODFILE="/\${KERNEL}.tar.gz"
for i in /*.tar.gz
do
	if [ "\$i" != "\$MODFILE" -a -f "\$i" ] ; then
		rm -f \$i
	fi
done
# untar kernel moules
tar -xzf \$MODFILE -C /lib/modules
rm -f \$MODFILE

# load all modules
EOTOP
###############################################################################
###############################################################################
# now put modprobe calls in for all the drivers

for i in $modules
do
	echo "modprobe $i" >> $DIR/init
done

# finish up the script
###############################################################################
###############################################################################
cat << EOBOT >> $DIR/init

# set up LVM
lvm vgscan --mknodes --ignorelockingfailure
lvm vgchange -ay --ignorelockingfailure

# find the root device ...
ROOT=\`cat /proc/cmdline |tr ' ' '\n' |grep '^root' |awk -F = '{print \$2}'\`

# try to figure out the filesystem from the fstab.gz ... it might
# be worth mounting with no args, reading the fstab in root, then
# remounting with the right options so it's easier to switch distros
# with the single initrd
if [ "x\$ROOT" != "x" -a -e "\$ROOT" -a -f /etc/fstab.gz ] ; then
	type=\`gunzip -c /etc/fstab.gz |grep "^\$ROOT" |awk '{print \$3}'\`
else
	type="ext2"
fi

echo "ROOT IS \$ROOT, type \$type"

mount -t \$type \$ROOT /realroot
if [ $? -ne 0 ] ; then
	echo "Unable to mount \$ROOT on /realroot - spawning interactive shell."
	exec /bin/sh -i
fi

# install pivot_root to the system root if it's not there ... if you're
# hardcore/paranoid, make this a statically compiled pivot_root
if [ ! -x /realroot/bin/pivot_root ] ; then
	cp -a /bin/pivot_root /realroot/bin/pivot_root
fi

# kernel parameter "ishell" - launches an interactive shell
if (grep -q ishell /proc/cmdline) ; then
	echo "Launching interactive shell ..."
	/bin/sh -i
fi

###
### comment everything from here to EOBOT to make testing in a chroot easier
###

# move all the mounted filesystems to the real root
mount -n -o move /sys /realroot/sys
mount -n -o move /proc /realroot/proc
mount -n -o move /dev /realroot/dev

PATH=/bin:/sbin:/realroot/bin:/realroot/sbin

# all done!   pivot over to it - we're trusting that the OS will unmount
# /initrd automatically - add it to your rc.local equivalent if it doesn't
echo "Pivoting and execing /sbin/init!  Here we go!"
mkdir -p /realroot/initrd
cd /realroot
pivot_root . initrd
exec chroot . /sbin/init <dev/console >dev/console 2>dev/console 

EOBOT

###############################################################################
###############################################################################
# create an unmount script for convenience when testing

cat >$DIR/unmount <<EOMOUNT
#!/bin/sh

umount ./proc >/dev/null 2>&1
mount none ./proc -t proc
umount ./realroot
umount ./dev
umount ./sys
umount ./proc

EOMOUNT
###############################################################################

# hose up permissions
chmod -R 755 $DIR

# make the CPIO archive - the "-H newc" is important
echo "Creating $TARGET_FILE ..."
cd $DIR
find . |cpio -o -H newc 2>/dev/null > $DIR.cpio
gzip $DIR.cpio
mv $DIR.cpio.gz $TARGET_FILE


