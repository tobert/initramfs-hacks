#!/bin/sh
#
# This software is copyright (c) 2006-2010 by Al Tobey.
#
# This is free software; you can redistribute it and/or modify it under the terms
# of the Artistic License 2.0.  (Note that, unlike the Artistic License 1.0,
# version 2.0 is GPL compatible by itself, hence there is no benefit to having an
# Artistic 2.0 / GPL disjunction.)  See the file LICENSE for details.
#
# This script does basic qemu/kvm bridge port join/remove with the
# script= option for qemu.
#
# simply symlink it to kvm-ifup-$BRIDGE and kvm-ifdown-$BRIDGE and reference it on
# the qemu command line

export PATH=/sbin:/usr/sbin:/bin:/usr/bin

iface=$1
cmd=`echo $0 |awk -F- '{print $2}'`
bridge=`echo $0 |awk -F- '{print $3}'`

if [ -z "$cmd" -o -z "$bridge" ] ; then
    echo "Incorrect usage.  This script should be a symlink in the form of kvm-COMMAND-BRIDGE where COMMAND is 'ifup' or 'ifdown' and BRIDGE is a Linux bridge already configured and showing in brctl show'"
    exit 1
fi

RETVAL=0
case $cmd in
    ifup)
        ifconfig $iface promisc 0.0.0.0
        brctl addif $bridge $iface
        RETVAL=$?
        ;;
    ifdown)
        brctl delif $bridge $iface
        RETVAL=$?
        ;;
    default)
        ;;
esac

exit 0

