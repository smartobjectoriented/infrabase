.. _debootstrap:

Debootstrap rootfs
##################

Introduction
************

`Debootstrap <https://linux-sunxi.org/Debootstrap>`__ is a rootfs generator able to produce full distribution (Ubuntu or Debian based) rootfs. It can be used directly on the target or cross-compiled from a host computer.

Generating a rootfs
*******************
The procedure showed on the linux-sunxi in the Introduction explain how to quickly setup deboostrap and how to use it. The result is a folder containing the cross-compiled rootfs.
In our repo, the directory agency/debootsrap_rootfs contains the script to generate an Ubuntu 20.04 focal distro for arm64.


Usability in the Infrabase framework
************************************
Debootstrap is one of the simplest tool to generate an ARM based rootfs.

Pros:

 - Generate a distro based rootfs in < 30-min
 - Can generate on the host or the target
 - chroot customization, so it is really quick to tweak the rootfs on the host
 - Small (592M Debootstrap vs 2.3G Armbian)
 
Cons:

 - Limited in the distros list
 - Need some manual tweaks after the base creation to have a fully functional system.


This framework is really usefull to quickly bring up a full distro rootfs. Its ability to script its creation easily and to customize it in a chroot like manner is what make it stand out.