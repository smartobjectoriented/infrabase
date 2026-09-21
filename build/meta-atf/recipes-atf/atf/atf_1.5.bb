# Copyright (c) 2025-2026 EDGEMTech SA

SUMMARY = "ATF firmware"
DESCRIPTION = "ARM Trusted Firmware (ATF)"

LICENSE = "GPLv2"

inherit atf

# Version and revision
PR = "r0"
PV = "1.5"


SRC_URI = "git://git.trustedfirmware.org/TF-A/trusted-firmware-a.git;nobranch=1;protocol=https"
SRC_URI += "file://0001-atf-imx8mp-avz.patch"

FILESPATH:prepend = "${THISDIR}/files:"

SRCREV = "78b1610e31d9a5dbd16553b8a2ac99000a7379f7"

# do_patch uses the standard OE patch flow (applies to ${S} via SRC_URI).
# The patch uses git-style a/<rel> b/<rel> labels and applies cleanly with
# the default -p1 strip level.  do_attach_infrabase later copies ${S} into
# ${IB_TARGET} (= ${IB_ATF_PATH}) so the local working tree gets the patch.

# To force the task to be re-executed
do_build[nostamp] = "1"

# OP-TEE must be built before ATF — but only on the secure-world chain,
# where bsp_virt64.inc:__do_platform_boot_chain later bundles OP-TEE into
# the FIP via fiptool. On "atf+uboot" the FIP carries BL31+U-Boot only (no
# --tos-fw), and "uboot" never reaches this recipe. Gating on the chain
# avoids building OP-TEE for nothing.

do_build[depends] = "${@'optee:do_build' if d.getVar('IB_CHAIN_HAS_OPTEE') else ''}"
do_configure[noexec] = "1"

# Where the working directory will be placed in infrabase root dir
IB_TARGET = "${IB_ATF_PATH}"

do_build () {

	if [ "${IB_PLATFORM}" = "verdin-imx8mp" ]; then
		BL31="${IB_ATF_PATH}/build/imx8mp/release/bl31.bin"
		HASH_FILE="${BL31}.sha256"
		OLD_HASH="$(cat $HASH_FILE 2>/dev/null || true)"
		NEW_HASH="$(sha256sum $BL31 2>/dev/null | cut -d' ' -f1 || true)"
		if [ -f "$BL31" ] && [ -n "$NEW_HASH" ] && [ "$OLD_HASH" = "$NEW_HASH" ]; then
			echo "ATF bl31.bin is up to date, skipping rebuild"
		else
			do_build_bl31
			sha256sum "$BL31" | cut -d' ' -f1 > "$HASH_FILE"
		fi
	elif [ "${IB_PLATFORM}" = "virt64" ]; then
		do_build_all_fiptool
		mkdir -p ${IB_DIR}/filesystem
		cp ${IB_ATF_PATH}/build/qemu/release/bl1.bin ${IB_DIR}/filesystem/
		cp ${IB_ATF_PATH}/build/qemu/release/bl31.bin ${IB_DIR}/filesystem/

	elif [ "${IB_PLATFORM}" = "rpi4_64" ]; then

		# TF-A's rpi4 port is BL31-only (RESET_TO_BL31 := 1 in its
		# platform.mk): there is no BL1/BL2 and no FIP, because the GPU
		# firmware plays the role of the earlier stages and loads
		# bl31.bin directly as the armstub. Hence do_build_bl31 and not
		# do_build_all_fiptool. The upstream doc is explicit that the
		# port has "no real configuration options" — one universal
		# binary — so IB_ATF_EXTRA_OPTS is left empty for this platform.
		#
		# The result is consumed by bsp_rpi4_64.inc, which copies it to
		# p1 as bl31.bin and appends the armstub= lines to config.txt.

		BL31="${IB_ATF_PATH}/build/${IB_ATF_PLAT}/release/bl31.bin"
		HASH_FILE="${BL31}.sha256"
		OLD_HASH="$(cat $HASH_FILE 2>/dev/null || true)"
		NEW_HASH="$(sha256sum $BL31 2>/dev/null | cut -d' ' -f1 || true)"
		if [ -f "$BL31" ] && [ -n "$NEW_HASH" ] && [ "$OLD_HASH" = "$NEW_HASH" ]; then
			echo "ATF bl31.bin is up to date, skipping rebuild"
		else
			do_build_bl31
			sha256sum "$BL31" | cut -d' ' -f1 > "$HASH_FILE"
		fi
	fi
}

addtask do_build

do_clean[nostamp] = "1"
do_clean () {
	rm -rf ${IB_ATF_PATH}/build/${IB_ATF_PLAT}
}
addtask do_clean