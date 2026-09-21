# Copyright (c) 2026 EDGEMTech SA

SUMMARY = "MCUboot bootloader"
DESCRIPTION = "MCUboot, the secure bootloader the Zephyr boot chain hands over to, \
carrying this tree's AArch64 support"
LICENSE = "Apache-2.0"

inherit zephyr

# Version and revision

PR = "r0"
PV = "2.4.0"

# Where the working directory sits in the infrabase root dir. This is the
# path west gives the module in its manifest (bootloader/mcuboot), because
# west is what resolves it at build time — see the note on SRCREV below.
IB_TARGET = "${IB_ZEPHYR_WORKSPACE}/bootloader/mcuboot"

# Fetched, like avz and linux, rather than embedded: MCUboot is upstream
# code we carry a patch series against.
#
# SRCREV is the commit zephyr/west.yml pins for the mcuboot module, and it
# has to STAY that commit. west resolves the module from the same manifest
# and will happily reset a tree that disagrees with it, so a bump here is a
# bump there — move both in one commit, the way avz moves SRCREV and
# IB_SO3_TAG together.
#
# IB_MCUBOOT_TAG records the human-readable version SRCREV corresponds to.

IB_MCUBOOT_TAG = "v2.4.0-150-gaa32eaaa"
SRC_URI = "git://github.com/zephyrproject-rtos/mcuboot.git;nobranch=1;protocol=https"
SRCREV = "aa32eaaad41cc345e6f6e6633368a4766fe23c25"

# The patch series, named and laid out like every other component's — see
# meta-linux/recipes-linux/linux/linux_6.12.bb, which is where both of these
# lines come from. The FILESPATH prepend is what lets the SRC_URI entries in
# the .inc name the patches without repeating the directory.
FILESPATH:prepend = "${THISDIR}/files/0001-${PF}:"
require files/0001-${PF}-patches.inc

# MCUboot is compiled by west, as one of the images usr-zephyr builds
# (IB_ZEPHYR_BOOT_APP). This recipe exists to own the SOURCE: fetch it, hold
# the series against it, and put the patched result where west expects it.
do_configure[noexec] = "1"
do_build[noexec] = "1"
