#!/bin/bash
#
# This software is copyright (c) 2006-2010 by Al Tobey.
#
# This is free software; you can redistribute it and/or modify it under the terms
# of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
# version 2.0 is GPL compatible by itself, hence there is no benefit to having an
# Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.
#
# Build an initramfs from files on the host system (currently assumed Debian
# but easy to adjust).
#
# The initramfs will boot up to networking support using DHCP then pull
# an image tarball down over HTTP.   The tarball is unwrapped over root
# and booted as if it was on a root disk.   With minimal preparation,
# most distros work just fine this way if you're willing to give up
# 200-1024MB of RAM for root storage.
#
# The tarball mostly needs a stripped-down fstab and a couple other simple
# mods to run this way.   Generally I haven't needed to mess with the default
# system init scripts on Debian, and I assume Ubuntu and Redhat variants will
# be fine.
#
# /dev/sda (with sfdisk) and write out there, configure grub, etc. then
# chroot and fire up chef to finish the job.    This made going from a
# slightly configured deboostrap to full system happen in about 10 minutes,
# but all 100 systems could be fired off at once from IPMI/screen.

# require a default image tarball - this could be a rescue image
# it's also possible to pass an image url on the kernel command line
# from PXE/Grub
DEFAULT_IMAGE_TARBALL="$1"
if [ -n "$DEFAULT_IMAGE_TARBALL" ] ; then
    curl -s -I "$IMAGE_TARBALL" |head -n 1 |grep -q '2[0-9][0-9][[:space:]]\+OK'
    if [ $? -ne 0 ] ; then
        echo "HEAD request for image tarball at $IMAGE_TARBALL failed.  Bailing out before it's too late."
    fi
else
    echo "HTTP URL to an image tarball is required."
fi

DEFAULT_USERAGENT="http initramfs" # should be overridden with the host MAC
IMG=`tempfile`
INITRAMFS=`mktemp -d`
echo "Creating ramfs in $INITRAMFS"

# for now, rely on host OS for busybox, etc.
# Note, for >= 2.6.27 kernels you'll likely need a newer busybox than
# what Lenny or EL5 provide to support newer sysfs/udev and allow
# mdev -s to do its thing in lieu of messy udev integration here.
for pkg in busybox-static
do
    # TODO: debian specific - maybe just put a static busybox in git
    /usr/bin/dpkg -s $pkg |grep -q '^Status:.*installed'
    if [ $? -ne 0 ] ; then
        echo "This script will not work unless the '$pkg' package is installed."
        exit 1
    fi
done

# build up a skeleton
mkdir $INITRAMFS/bin
mkdir $INITRAMFS/proc
mkdir $INITRAMFS/sys
mkdir -p $INITRAMFS/var/lock
mkdir $INITRAMFS/tmp
mkdir $INITRAMFS/dev
mkdir $INITRAMFS/etc
mkdir $INITRAMFS/lib64
mkdir $INITRAMFS/newroot

# create symlinks
ln -s /lib64 $INITRAMFS/lib
ln -s /bin $INITRAMFS/sbin
ln -s / $INITRAMFS/usr

# install basics from host system
for file in /bin/busybox /dev/console /dev/zero /dev/null /dev/tty1
do
    cp -a $file "${INITRAMFS}${file}"
done

# set up busybox symlinks
# list built from Debian Lenny's busybox-static binary
cd $INITRAMFS/bin
for func in "[" "[[" sh ash basename bunzip2 bzcat bzip2 cat chmod chown chroot clear cmp cp cpio cut date dd df dirname dmesg du egrep env expr false fgrep find free getopt getty grep gunzip gzip halt head hostid hostname hwclock id ifconfig ifdown ifup ip ipcalc kill killall length less ln losetup ls lzmacat md5sum mdev mkdir mkfifo mknod mkswap mktemp more mount mv nameif nc netstat nslookup od patch pidof ping ping6 pivot_root poweroff printf ps pwd readlink realpath reboot renice reset rm rmdir route sed sh sha1sum sleep sort strings swapoff swapon sync tail tar tee telnet test tftp time top touch tr traceroute true udhcpc umount uname uncompress unexpand uniq unlzma unzip uptime uudecode uuencode vi watch wc wget which xargs yes zcat echo
do
    ln -s busybox "$func"
done
# ] ]] (make vim syntax happy)

# write out some basic config files
echo "root:x:0:0::/:/bin/sh" > $INITRAMFS/etc/passwd
echo "root:x:0:" > $INITRAMFS/etc/group
# take root password from host system
grep '^root:' /etc/shadow > $INITRAMFS/etc/shadow

# create init script
# be careful to escape internal variables where necessary
cat << EOF > $INITRAMFS/init
#!/bin/sh

export PATH=/bin
export LD_LIBRARY_PATH=/lib64:/lib:/bin

echo "Mounting kernel filesystems."
mount -n -t sysfs none /sys
mount -n -t proc none /proc
mount -n -t tmpfs -o mode=0755 udev /dev

mount -n -o size=25% -t tmpfs none /newroot
if [ \$? -ne 0 ] ; then
    echo "Mount of tmpfs for newroot failed - falling to rescue shell."
    exec /bin/sh -i
fi

# bring up networking - first pass times out in less than a minute
# but should be instant as long as dhcp is working correctly
# later on we'll try again with a much longer timeout, then fall to
# rescue shell
success=0
for ifacex in /sys/class/net/eth*
do
    iface=\`basename \$ifacex\`
    carrier=\`cat \$ifacex/carrier 2>/dev/null\`
    if [ -z "\$carrier" ] ; then
        echo "Skipping interface '\$iface' since it appears to be unplugged."
    elif [ \$carrier -eq 1 ] ; then
        echo "Attempting DHCP network configuration of \$iface with busybox udhcpc ..."
        # try 3 times, waiting 15 seconds for a response, and 15 seconds between retries
        udhcpc -i \$iface -n -t 3 -T 15 -A 15 -s /etc/udhcpc.script
        [ \$? -eq 0 ] && ((success++))
    fi
done

# on failure on all interfaces, try again on just eth0 waiting a long time
if [ \$success -lt 0 ] ; then
    echo "Previous attempts to get an address failed.   DHCP will block for an hour then drop to a shell."
    udhcpc -i eth0 -n -b -t 10 -T 30 -A 60 -s /etc/udhcpc.script
    if [ \$? -eq 0 ] ; then
        echo "Failed to get an address on eth0 after an hour.  Dropping to a rescue shell."
        exec /bin/sh -i
    fi
fi

# TODO: untested ...
image_url=\`tr ' ' '\\n' </proc/cmdline |awk -F= '/^image_url/{print $2}'\`
if [ $? -ne 0 -o -z "\$image_url" ] ; then
    echo "Fetching system tarball from default URL: '$DEFAULT_IMAGE_TARBALL'"
    image_url="$DEFAULT_IMAGE_TARBALL" # set by make_http_initramfs.sh
else
    echo "Fetching system tarball from kernel command line URL: '\$image_url' ..."
fi

# fetch/untar the system image directly to the new root
ETHMAC=\`ip link show eth0 |awk '/ether /{print $2}' |sed 's/://g'\`
[ \$? -ne 0 ] && ETHMAC="$DEFAULT_USERAGENT"
wget -U "$ETHMAC" -O - \$image_url |gunzip -c - |tar -C /newroot -xvf -
if [ \$? -eq 0 ] ; then
    echo "System installation to tmpfs failed.  Dropping to a rescue shell."
    exec /bin/sh -i
fi

# move utility filesytems to the new root
mount -n -o move /sys /newroot/sys
mount -n -o move /proc /newroot/proc
rmdir /proc ; ln -s /newroot/proc /proc
mount -n -o move /dev /newroot/dev
mv /dev /old_dev ; ln -s /newroot/dev /dev

# all set, pivot into the root and fire up init
echo "Pivoting into real root and switching to /sbin/init ..."
mkdir -p /newroot/initramfs
cd /newroot
pivot_root . initramfs
exec chroot . /sbin/init <dev/console >dev/console 2>dev/console

echo "Something seems to have gone terribly wrong.  This shouldn't be possible.  Dropping to a rescue shell for diagnosis, but plan on rebooting."
exec /bin/sh -i

EOF
chmod 755 $INITRAMFS/init

# for some stupid reason this isn't in the busybox package
# so just embed a revised edition here
cat << EOF > $INITRAMFS/etc/udhcpc.script
#!/bin/sh

[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="/$subnet"

case "$1" in
	deconfig)
        ip addr flush $interface
		;;

	renew|bound)
        ip addr add dev $interface $ip$NETMASK $BROADCAST

		if [ -n "$router" ] ; then
            ip route flush dev $interface
			metric=0
			for i in $router ; do
                ip route add default dev $interface via $i metric $((metric++)) 
			done
		fi

        rm -f /etc/resolv.conf
		[ -n "$domain" ] && echo search $domain >> /etc/resolv.conf
		for i in $dns ; do
			echo nameserver $i >> /etc/resolv.conf
		done
		;;
esac

exit 0
EOF
chmod 755 $INITRAMFS/etc/udhcpc.script

echo
SIZE=`du -hsc $INITRAMFS |awk '/total/{print $1}'`
echo "Uncompressed size of initramfs is $SIZE."
echo

echo -n "Creating archive $IMG ..."
cd $INITRAMFS
find . |cpio -o -H newc 2>/dev/null |gzip -c > $IMG
echo " done."

chmod 644 $IMG

