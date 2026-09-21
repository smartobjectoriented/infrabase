# Copyright (c) 2026 EDGEMTech SA

SUMMARY = "Zephyr Board Support Package"
DESCRIPTION = "Zephyr BSP. Offers the same boot modes as bsp-linux — bare \
U-Boot, ATF+OP-TEE+U-Boot, and the full chain with Zephyr as an AVZ guest \
— selected by IB_BOOT_CHAIN. The one structural difference is that Zephyr \
is an executive: the application is linked into the image, so there is no \
rootfs anywhere in the picture."

LICENSE = "GPLv2"

PV = "1.0"
PR = "r0"

inherit filesystem
inherit uboot
inherit logging
inherit bsp

# ITS templates live in this layer, rendered into IB_ITB_PATH by the shared
# do_render_its (bsp.bbclass) before do_itb.
IB_ITS_SRC = "${THISDIR}/files/its"

# :append (not +=) so no space is inserted before ":zephyr" — otherwise the
# preceding CPU token parses as "aarch64 " and :<cpu> overrides stop
# matching. Same rationale as bsp-so3. This is what selects
# IB_ITB_PATH:zephyr, so the ITB lands in zephyr/images rather than
# linux/images.
OVERRIDES:append = ":zephyr"

include ../bsp/files/bsp_${IB_PLATFORM}.inc

# ITS selection, exactly as bsp-linux and bsp-so3 do it:
#
#   bare modes  (IB_BOOT_CHAIN uboot / atf+uboot)
#       ${IB_PLATFORM}.its           Zephyr booted by bootm, no hypervisor
#
#   full mode   (IB_BOOT_CHAIN full)
#       ${IB_TARGET_ITS}.its         the AVZ bundle
#       <base>${IB_GUEST_SUFFIX}.its the Zephyr guest AVZ starts
#
# A name ending in "_avz" is what selects the two-ITB shape, here and in
# __deploy_arm_common — keep the two keyed off the same thing. Override
# IB_TARGET_ITS:zephyr:<plat> in local.conf to pick, the same way
# IB_TARGET_ITS:linux:<plat> does for Linux. Bare by default: that is the
# mode verified end to end.
IB_TARGET_ITS ?= "${IB_PLATFORM}"

# What AVZ starts is the FIRST image of the chain, and that is the
# bootloader whenever there is one.
#
# The application cannot be it: with IB_ZEPHYR_BOOT_APP set, the
# application is built as the bootloader's payload — linked for the slot,
# to be RAM-loaded there — so entering it directly hands AVZ code compiled
# for another address, and the guest reads through a wild pointer on its
# first instructions ("Unhandled data read at 0x130"). Deriving the suffix
# here means there is one guest ITB and it is the right one, rather than a
# uEnv in each configuration deciding which of two to load.
IB_GUEST_SUFFIX = "${@'_mcuboot_guest' if d.getVar('IB_ZEPHYR_BOOT_APP') else '_zephyr_guest'}"

# IB_BOOT_CHAIN="mcuboot": the bootloader is the first thing the machine
# runs, written by bsp_${IB_PLATFORM}.inc to the raw area at the head of the
# card for the boot ROM to find. The plain binary, because that is what a ROM
# copies — and therefore the load address has to be stated here rather than
# read out of program headers.
#
# 0x41000000 is where MCUboot is linked: the board's CONFIG_SRAM_BASE_ADDRESS,
# the same address the ITB gives it in the other two chains. One address for
# the bootloader in all three, so nothing about the image changes with the
# chain that starts it.
IB_FIRST_STAGE_BIN = "${IB_ZEPHYR_USR_PATH}/build/${IB_ZEPHYR_BOOT_APP}/zephyr/zephyr.bin"
IB_FIRST_STAGE_LOAD = "0x41000000"

COMPATIBLE_PLATFORM = "virt64"

do_configure[noexec] = "1"
do_attach_infrabase[noexec] = "1"

# U-Boot is the whole boot chain here; usr-zephyr builds the payload.
# Except under IB_BOOT_CHAIN="mcuboot", where there is no U-Boot at all —
# asking for it would build a component nothing then loads.
IB_UBOOT_DEP = "${@'' if d.getVar('IB_BOOT_CHAIN') == 'mcuboot' else 'uboot:do_build'}"
do_build[depends] = "usr-zephyr:do_build ${IB_UBOOT_DEP}"

do_build () {
	bbplain "Everything built OK ..."
}
addtask do_build

####################### ITB

do_itb[nostamp] = "1"
do_itb[depends] += "usr-zephyr:do_build"
do_itb () {

	# An ITB exists to be read by U-Boot. Under IB_BOOT_CHAIN="mcuboot"
	# there is none: QEMU enters the bootloader ELF directly and the
	# bootloader reads its slot, so every artefact below would be built
	# and then never opened.
	if [ "${IB_BOOT_CHAIN}" = "mcuboot" ]; then
		bbplain "IB_BOOT_CHAIN=\"mcuboot\": no ITB, the bootloader is entered directly"
		return
	fi

	if [ ! -f "${IB_ZEPHYR_IMAGE}" ]; then
		bbfatal "No Zephyr image at ${IB_ZEPHYR_IMAGE} — usr-zephyr should have built it. Select the application with IB_ZEPHYR_APP, or point IB_ZEPHYR_IMAGE elsewhere in local.conf."
	fi

	# The FDT is ours and tiny; compile it here rather than dragging in a
	# Linux kernel tree for a device tree Zephyr never reads. Both the bare
	# and the guest ITS carry it. See files/its/${IB_PLATFORM}_fdt.dts.
	mkdir -p ${IB_ITB_PATH}
	if [ ! -f "${IB_ITS_SRC}/${IB_PLATFORM}_fdt.dts" ]; then
		bbfatal "No FDT source at ${IB_ITS_SRC}/${IB_PLATFORM}_fdt.dts"
	fi
	dtc -I dts -O dtb -o ${IB_ZEPHYR_FDT} ${IB_ITS_SRC}/${IB_PLATFORM}_fdt.dts

	# The pre-application image, when the chain has one (MCUboot on the
	# hardware, its stand-in here). Built unconditionally of whether this
	# boot will use it: U-Boot hands over to it when the boot target says
	# so, and that is decided at boot from storage, not here.
	#
	# Two shapes, and the tree provides both because both are real:
	#
	#   ${IB_PLATFORM}_mcuboot.its         entered by bootm, no hypervisor
	#   ${IB_PLATFORM}_mcuboot_guest.its   started by AVZ at EL1
	#
	# Which one is selected by the same thing that selects every other ITS
	# here — the "_avz" suffix on IB_TARGET_ITS — so a tree cannot end up
	# with a bootloader of one shape and a chain of the other. A tree whose
	# chain carries AVZ gets the guest variant; the bare one is what a
	# tree without AVZ boots.
	#
	# Rendered from this recipe rather than by the shared do_render_its: the
	# generic renderer walks a fixed list of names (bare, target, guest) and
	# has no business learning about a Zephyr-specific slot.
	if [ -n "${IB_ZEPHYR_BOOT_APP}" ]; then
		if [ ! -f "${IB_ZEPHYR_BOOT_IMAGE}" ]; then
			bbfatal "No pre-application image at ${IB_ZEPHYR_BOOT_IMAGE} — usr-zephyr builds it from IB_ZEPHYR_BOOT_APP='${IB_ZEPHYR_BOOT_APP}'"
		fi

		case "${IB_TARGET_ITS}" in
		*_avz)	boot_its=${IB_PLATFORM}_mcuboot_guest ;;
		*)	boot_its=${IB_PLATFORM}_mcuboot ;;
		esac

		if [ ! -f "${IB_ITS_SRC}/$boot_its.its" ]; then
			bbfatal "No pre-application ITS at ${IB_ITS_SRC}/$boot_its.its"
		fi
		bsp_render_its $boot_its
		mkimage -f ${IB_ITB_PATH}/$boot_its.its \
			${IB_ITB_PATH}/$boot_its.itb
	fi

	case "${IB_TARGET_ITS}" in
	*_avz)
		# Two ITBs: the AVZ bundle and the Zephyr guest AVZ starts.
		# Output names must be what __deploy_arm_common looks for.
		if [ ! -f "${IB_ITB_PATH}/${IB_TARGET_ITS}.its" ]; then
			bbfatal "ITS '${IB_TARGET_ITS}' selected by IB_TARGET_ITS:zephyr:${IB_PLATFORM} has no template in ${IB_ITS_SRC}"
		fi
		mkimage -f ${IB_ITB_PATH}/${IB_TARGET_ITS}.its ${IB_ITB_PATH}/${IB_TARGET_ITS}.itb

		# The guest is whatever IB_GUEST_SUFFIX names: this recipe's
		# own Zephyr image by default, or a product's payload when a
		# layer overrides the suffix (meta-e1c-zephyr-dev sets "_e1c"
		# and renders the ITS from its own task before this one runs).
		# Same derivation as bsp-linux and bsp-so3 — nothing here needs
		# to know whether a capsule exists.
		guest_its=$(echo "${IB_TARGET_ITS}" | sed 's/_avz$//')${IB_GUEST_SUFFIX}
		if [ ! -f "${IB_ITB_PATH}/$guest_its.its" ]; then
			bbfatal "No guest ITS at ${IB_ITB_PATH}/$guest_its.its" \
				"(IB_TARGET_ITS=${IB_TARGET_ITS}," \
				"IB_GUEST_SUFFIX=${IB_GUEST_SUFFIX})"
		fi
		mkimage -f ${IB_ITB_PATH}/$guest_its.its ${IB_ITB_PATH}/$guest_its.itb
		;;
	"")
		bbfatal "No ITS selected for platform '${IB_PLATFORM}': set IB_TARGET_ITS:zephyr:${IB_PLATFORM} in build/conf/local.conf (available: $(cd ${IB_ITS_SRC} 2>/dev/null && ls -1 ${IB_PLATFORM}.its ${IB_PLATFORM}_*.its 2>/dev/null | sed -e 's/\.its$//' -e '/${IB_GUEST_SUFFIX}$/d' | tr '\n' ' '))"
		;;
	*)
		# Single ITB, bootm'd straight by U-Boot.
		if [ ! -f "${IB_ITB_PATH}/${IB_TARGET_ITS}.its" ]; then
			bbfatal "No ITS at ${IB_ITB_PATH}/${IB_TARGET_ITS}.its (do_render_its should have produced it from ${IB_ITS_SRC})"
		fi
		mkimage -f ${IB_ITB_PATH}/${IB_TARGET_ITS}.its ${IB_ITB_PATH}/${IB_TARGET_ITS}.itb
		;;
	esac
}

####################### Deploy

# The pre-application image and slot 0, when the chain has one. Shared,
# because two deploys need it and neither owns it: the plain one below, and
# a product's replacement of __do_platform_deploy (meta-e1c-zephyr-dev has
# one). Returns what it staged, so the caller can report it.
#
# Everything here is conditional on IB_ZEPHYR_BOOT_APP. A tree that boots its
# application directly calls this and nothing happens, which is why the two
# callers do not have to ask first.

def __deploy_zephyr_boot_app(d, p1):
    import os
    import subprocess

    staged = []

    if not d.getVar('IB_ZEPHYR_BOOT_APP'):
        return staged

    # Under IB_BOOT_CHAIN="mcuboot" the bootloader is staged as an ELF by
    # __do_platform_boot_chain, for QEMU to enter directly; there is no ITB
    # and no U-Boot to load one. Slot 0 below is then the whole deploy.
    boot_itb_wanted = (d.getVar('IB_BOOT_CHAIN') or "") != "mcuboot"

    IB_ITB_PATH = d.getVar('IB_ITB_PATH')
    IB_PLATFORM = d.getVar('IB_PLATFORM')
    fs          = d.getVar('IB_FILESYSTEM_PATH')

    # In whichever of its two shapes this configuration asked for: entered by
    # AVZ at EL1 (_mcuboot_guest) or by bootm with no hypervisor under it
    # (_mcuboot). Selected by the "_avz" suffix on IB_TARGET_ITS, the same
    # test do_itb makes when it decides which one to build — one criterion,
    # so the card cannot end up with a bootloader of one shape and a chain of
    # the other.
    #
    # Not "whichever ITB is present in IB_ITB_PATH": that directory keeps
    # what previous configurations built, and staging on presence put both
    # shapes on p1, the stale one included.
    #
    # Staged under its own name rather than a common one, so what is on p1
    # says which it is; the other is removed for the same reason.
    if boot_itb_wanted:
        its = d.getVar('IB_TARGET_ITS') or ""
        want = f"{IB_PLATFORM}_mcuboot_guest" if its.endswith("_avz") \
               else f"{IB_PLATFORM}_mcuboot"
        other = f"{IB_PLATFORM}_mcuboot" if its.endswith("_avz") \
                else f"{IB_PLATFORM}_mcuboot_guest"

        boot_itb = os.path.join(IB_ITB_PATH, want + ".itb")
        if not os.path.isfile(boot_itb):
            bb.fatal(f"{boot_itb} is missing — do_itb builds it from "
                     f"IB_ZEPHYR_BOOT_APP='{d.getVar('IB_ZEPHYR_BOOT_APP')}'")

        subprocess.run(['cp', boot_itb, os.path.join(p1, want + ".itb")], check=True)
        staged.append(want + ".itb")

        stale = os.path.join(p1, other + ".itb")
        if os.path.isfile(stale):
            bb.note(f"removing stale {other}.itb from the boot partition")
            os.remove(stale)

    # Slot 0. Written to the raw partition rather than into a filesystem:
    # that is what a slot is, and it is how the Factory Capsule will write
    # the next image too. dd and not cp — p2 has no filesystem to copy into.
    #
    # The image is the signed one: MCUboot verifies it against the key it
    # embeds, and reads the load address out of the header imgtool wrote.
    signed = os.path.join(d.getVar('IB_ZEPHYR_USR_PATH'), "build",
                          d.getVar('IB_ZEPHYR_APP'), "zephyr", "zephyr.signed.bin")
    #
    # Written into the storage image at p2's offset rather than through a
    # loop partition: the wrapper around this function has p1 mounted, the
    # loop name is whatever losetup handed out this time, and the offset is
    # fixed by the layout (fs_arm_common.bbclass, "ab"). conv=notrunc so the
    # rest of the image survives, and the seek is in MiB to match.
    # work/, not the filesystem/ symlink beside it: the symlink is created
    # by __do_fs_init_storage and so is absent whenever the image was already
    # there and only do_fs_check ran. The mount uses this path too.
    store = os.path.join(fs, "work", f"sdcard.img.{IB_PLATFORM}")
    slot0_mib = 257

    if not os.path.isfile(signed):
        bb.warn(f"no signed image at {signed} — slot 0 left as it was")
    elif not os.path.isfile(store):
        bb.warn(f"no storage image at {store} — slot 0 left as it was")
    else:
        subprocess.run(['dd', f"if={signed}", f"of={store}",
                        'bs=1M', f"seek={slot0_mib}",
                        'conv=notrunc,fsync'], check=True)
        staged.append(f"{os.path.basename(signed)} -> slot 0 (p2)")

    return staged


# Replaces the one bsp_${IB_PLATFORM}.inc defines, which knows only about
# uEnv.txt and the target ITB. Everything OS-agnostic still comes from it
# through __deploy_arm_common; the bootloader and its slot are what a Zephyr
# BSP adds.
def __do_platform_deploy(d):
    import os

    # uEnv.txt and the target ITB are U-Boot's, so under
    # IB_BOOT_CHAIN="mcuboot" there is nothing for p1 to hold — only the
    # slot the bootloader reads.
    if (d.getVar('IB_BOOT_CHAIN') or "") != "mcuboot":
        __deploy_arm_common(d)

    p1 = os.path.join(d.getVar('IB_FILESYSTEM_PATH'), "p1")
    staged = __deploy_zephyr_boot_app(d, p1)

    if staged:
        bb.plain("Deployed on p1: " + ", ".join(staged))


do_deploy[nostamp] = "1"
# filesystem:do_fs_check creates the storage image when it is missing, the
# same dependency bsp-linux and bsp-torizon declare. Without it a deploy on
# a fresh checkout dies with "the filesystem for platform ... has not been
# initialised yet" and tells the user to run init_storage.sh — which is
# exactly what this dependency is for, and is why CI cannot run init_storage
# by hand. Three tasks need it: both deploys mount p1, and the boot chain
# writes the first stage into the card's raw area.
do_deploy[depends] += "filesystem:do_fs_check ${IB_UBOOT_DEP}"
do_deploy_boot[depends] += "filesystem:do_fs_check"
do_deploy_boot_chain[depends] += "filesystem:do_fs_check"
python do_deploy() {

    bb.plain("Deploy Zephyr ITB and U-boot")

    __do_deploy_boot(d)
}
# before do_build as well as do_deploy, like bsp-linux: `build.sh
# bsp-zephyr` should leave a usable ITB behind, not just a green log.
addtask do_itb before do_build before do_deploy
addtask do_deploy

do_deploy_boot[nostamp] = "1"
python do_deploy_boot() {

    bb.plain("Deploy Zephyr boot (u-boot, itb)")

    __do_deploy_boot(d)
}
addtask do_itb before do_deploy_boot
addtask do_deploy_boot

do_clean[depends] = "${@'' if d.getVar('IB_BOOT_CHAIN') == 'mcuboot' else 'uboot:do_clean'}"
do_clean[nostamp] = "1"
do_clean () {
	rm -f ${TMPDIR}/stamps/bsp-zephyr*
}
addtask do_clean
