# Copyright (c) 2025-2026 EDGEMTech SA

SUMMARY = "Linux Operating System"
DESCRIPTION = "Linux OS with Toradex patches to run Verdin family boards"
LICENSE = "GPLv2"

# Release and version
PR = "r0"
PV = "6.6-verdin"

OVERRIDES += ":linux"

inherit linux

SRC_URI = "git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git;tag=v6.6.94;nobranch=1;protocol=https"
SRCREV = "6282921b6825fef6a1243e1c80063421d41e2576"

# Set of patches to be applied

FILESPATH:prepend = "${THISDIR}/files/0001-${PF}:"

require files/0001-${PF}-patches.inc
require linux-deploy.inc

# Where the working directory will be placed in infrabase root dir
IB_TARGET = "${IB_LINUX_PATH}"

do_configure[nostamp] = "1"
do_configure () {
	cd ${IB_TARGET}
	make ${IB_CONFIG}
}

do_build () {
	echo "Building Linux with ${CORES} cores..."
	
	cd ${IB_TARGET}
	
	make -j${CORES} Image
	  
	# Compile the device tree files
	make dtbs
}

do_clean[nostamp] = "1"
python do_clean () {
    __do_clean(d)
}
addtask do_clean
