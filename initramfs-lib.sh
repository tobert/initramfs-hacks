#!/bin/bash

# functions shared across tools
#
# This software is copyright (c) 2006-2010 by Al Tobey.
#
# This is free software; you can redistribute it and/or modify it under the terms
# of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
# version 2.0 is GPL compatible by itself, hence there is no benefit to having an
# Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.

# pull a host binary and all of its dependencies into the new root
installfile () {
    util=$1
    butil=`basename $util`

    if [ -z "$util" ] ; then
        echo "Must specify what utility to install."
        exit 1
    fi

    if [ -e $INITRAMFS/bin/$butil ] ; then
        echo "A version of '$butil' already exists.  Skipping installation."
    fi

    # find the file to be installed in the host system
    if [ ! -e "$util" ] ; then
        xutil=`which $util`
        bindir="bin"
        if [ -n "$xutil" -a -e $xutil ] ; then
            util=$xutil
        elif [ -e "/usr/lib/$util" ] ; then
            bindir="lib64"
            util="/usr/lib/$util"
        elif [ -e "/lib/$util" ] ; then
            bindir="lib64"
            util="/lib/$util"
        else
            echo "Could not determine where to find "$util".   Try using the full path."
            exit 1
        fi
    fi
    
    for dep in `ldd $util |awk '{print $3}' |grep '^/'`
    do
        bname=`basename $dep`
        echo -n "checking dependency $bname ..."
        if [ -e $INITRAMFS/lib64/$bname ] ; then
            echo "found."
        else
            echo "not found."
            echo "Installing $dep in \$ROOT/lib64/$bname"
            cp $dep $INITRAMFS/lib64/$bname
        fi
    done
    
    echo -n "Copying $util to $bindir/$butil ..."
    cp $util $INITRAMFS/$bindir/$butil
    echo "done."
}

# remove blatantly useless kernel modules
remove_useless_kmods () {
    KROOT="$1"
    if [ -z "$KROOT" ] ; then
        echo "Cowardly refusing to mess with system kernel.   Call this function with a chroot argument."
        exit 1
    fi

    echo -n "Removing unnecessary kernel modules ... sound "
    rm -rf $KROOT/lib/modules/*/kernel/sound

    for kdirname in atm bluetooth edac ieee1394 infiniband isdn leds media message mmc mtd parport pcmcia spi telephony w1
    do
        echo -n "$kdirname "
        rm -rf $KROOT/lib/modules/*/kernel/drivers/$kdirname
    done
    
    for kdirname in 9p affs autofs befs binfmt_misc.ko coda cramfs exportfs hfsplus jffs2 nfsd ntfs qnx4 reiserfs smbfs udf adfs afs autofs4 bfs cifs efs freevxfs hfs hpfs jffs jfs minix ncpfs ocfs2 romfs sysv ufs
    do
        echo -n "$kdirname "
        rm -rf $KROOT/lib/modules/*/kernel/fs/$kdirname
    done
    
    for kdirname in 802 appletalk ax25 dccp econet ipx netrom rxrpc tipc x25 atm bluetooth decnet ieee80211 irda lapb rose wanrouter
    do
        echo -n "$kdirname "
        rm -rf $KROOT/lib/modules/*/kernel/net/$kdirname
    done

    echo "done."
    unset kdirname KROOT
}

