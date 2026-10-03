.. _buildroot2:

Buildroot
#########

Introduction
************
`Buildroot <https://buildroot.org/>`__ is a framework to generate distroless linux system.

Generating a rootfs
******************* 
Buildroot can be used to only generate a rootfs and/or the kernel/bootloader. It allows to have custom environnement, using a separate kernel.


Usability in the Infrabase framework
************************************ 
Buildroot is powerfull and well known, but it lacks the availability of APT to ease the developpement. 

Pros:

 - Very small (167M).
 - Easy to customize.

Cons:

 - No APT support.

