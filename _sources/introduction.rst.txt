.. _introduction:

Introduction
============

``Infrabase`` provides the developer with a base environment to deal with embedded software to be deployed on
different hardware and emulated boards.

``Infrabase`` harnesses the power of BitBake's highly modular, recipe-driven architecture while seamlessly integrating prebuilt packages into the BitBake ecosystem. This approach is grounded in years of hands-on experience with R&D projects and embedded Linux development, where the typical software stack includes:

- A bootloader like U-Boot
- The Linux kernel
- The root filesystem
- A set of user-space applications

What it produces
****************

From a single ``build.sh bsp-linux`` you get a complete, bootable system for the selected
platform: the bootloader (optionally behind an ATF/OP-TEE boot chain), a kernel and its device
tree packed into a FIT image, a root filesystem built with *buildroot*, and the user-space
applications and kernel modules from ``linux/usr``. ``deploy.sh`` then writes all of it to a
loopback SD-card image, to a real device, or publishes it for a network install, and — on the
emulated platforms — ``st.sh`` boots the result under QEMU.

The supported platforms range from QEMU's ``virt`` machine in 32- and 64-bit to the Raspberry
Pi 4; they are listed in the :ref:`user guide <user_guide>`, and selecting one is a single
variable in ``build/conf/local.conf``.

Scope
*****

This repository is the **generic base**: a plain Linux system, and the machinery to fetch,
patch, build, deploy and run it. It is meant to be extended — product trees derive from it and
add their own layers (vendor BSPs, hypervisors, additional root filesystems) on top of the same
scripts and classes, and the base is kept aligned with them.

Two consequences are worth knowing up front: components are **fetched from upstream and patched
from tracked patchsets** rather than vendored, so your changes to a component live as patches
(see :ref:`the development flow <dev_flow>`); and ``bitbake`` here runs **unprivileged**, with
individual privileged operations escalating through ``sudo -n``.

