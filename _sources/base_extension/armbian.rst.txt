.. _armbian:

********************
Armbian full system
********************

Introduction
============
`Armbian <https://www.armbian.com/>`__ is a framework to quickly build a full system for msot ARM platform. It can produce kernel-only images or a ready-to-burn full image with rootfs and bootloader.

Build a system
==============
The `Armbian <https://github.com/armbian/build>`__ repo is the base tool to generate the images. Follow the steps in the link for more details about how to use it.


Usability in the EDGEMTech framework
====================================
Armbian is powerfull but only generate full system images.

Pros:

 - Uses config.txt to configure the system at boot time.
 - APT compatible.
 - Zero effort to flash.
 
Cons:

 - No rootfs customization
 - Needs the raspberry linux kernel.


In the end, it is nice to have it for quick tests, but becomes quickly limitating when we want to customize the environnement a bit.

