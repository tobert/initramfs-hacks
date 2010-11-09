Introduction and History
========================

This is a collection of shell tools I've hacked together on and off over the last
few years. It all started out as a reliable way to boot Xen with a Gentoo uClibc
userspace, which didn't really work when I started. I got tired of opening initramfs
archives and hacking them then realized they didn't need to be very sophisticated for
my case, so I built a very simple initramfs specifically for my kernels and hardware.

Some of this stuff has evolved slowly over time as I've used pieces in various work
projects. All of the code found in this project was written by me, on my own time,
on my own gear. Various versions may appear in past/present employers' source with
a full grant to use this code as they see fit; I retain copyright on the original
work but not the derivatives on their systems. I've re-created a couple pieces
for this project so I don't have to repeat myself in the future.

In general, this stuff is a toy for myself and like-minded embedded Linux hackers.
I put these on github because I've had a few random people express interest in
how I went about creating custom initramfs and diskless Linux images. Now they
can fork it all they want.

Most people should be using Dracut/genkernel/etc.. If you have specific needs and
don't feel like starting from scratch, feel free to take pieces and sections at
will. None of this is secret sauce or particularly hard to do; just tedious.

Applications
============

## make_initramfs.sh ##

Rather than building static kernels, this allows you to create minimal initramfs
with an exact list of modules to load rather than a wild guess. For systems with
more than one kernel installed, it bundles all kernels' support into a single
initramfs.

## test_initramfs.sh ##

This script simply unpacks /boot/initrd.cpio.gz and chroots into it for debugging.

## make_http_initramfs.sh ##

This one creates an initramfs that brings up networking with DHCP then sucks down
a tarball system image than it unpacks into tmpfs and chroots into for a diskless
linux that doesn't require a lot of modifications to mainstream distributions.

## initramfs_lib.sh ##

A couple functions that I've found handy in creating initramfs files but don't use
a lot in the scripts above right now. The ldd dependency copying is particularly
useful for quick and dirty utility copying from a base system.

## kvmtest.sh ##

Boot into linux in kvm/qmeu's curses console to test an image. This will almost definitely
require local editing to set MAC's (defaults should be reasonable for quick tests), bridges,
and adjust for different kvm/qemu versions' command line changes.

## kvm-ifupdown.sh ##

A simple qemu bridging script. Instructions are inside.

Copyright and License
=====================

This software is copyright (c) 2006-2010 by Al Tobey.

This is free software; you can redistribute it and/or modify it under the terms
of the Artistic License 2.0. (Note that, unlike the Artistic License 1.0,
version 2.0 is GPL compatible by itself, hence there is no benefit to having an
Artistic 2.0 / GPL disjunction.) See the file LICENSE for details.

