# Copyright (c) 2026 EDGEMTech SA

SUMMARY = "User space applications for Zephyr"
DESCRIPTION = "Zephyr applications living in zephyr/usr, built out of the \
west workspace in zephyr/ against an EDGE-M1 board. Unlike the Linux and \
SO3 user spaces these are not installed into a rootfs: a Zephyr image is \
the whole system, so the output is a binary that bsp-zephyr puts in the \
ITB."

LICENSE = "GPLv2"

PV = "1.0"
PR = "r0"

# zephyr.bbclass (meta-zephyr) declares where the workspace and MCUboot
# live, so those paths are stated once rather than repeated here.
inherit zephyr
inherit logging

# :append (not +=) so no space is inserted before ":zephyr" — see
# usr-so3_1.0.bb for the full rationale.
OVERRIDES:append = ":zephyr"

# Where the applications live, following <env>/usr like linux/usr.
IB_TARGET = "${IB_DIR}/zephyr/usr"

# Which application to build into the image. A Zephyr binary is a whole
# system, so there is exactly one of these.
IB_ZEPHYR_APP ?= "hello-ib"

# The image that boots BEFORE the application, when the boot chain has one:
# MCUboot on the real hardware, its stand-in here. It is a second, entirely
# separate Zephyr system that chain-loads the first — which is why it needs
# its own build rather than fitting the "one app" rule above.
#
# Empty by default: a tree that boots the application directly builds one
# image and behaves exactly as before.
IB_ZEPHYR_BOOT_APP ?= ""

# Where that image's sources are, and what the build needs on top of the
# board. An application under zephyr/usr needs none of it, which is why the
# defaults are the plain case; MCUboot needs all four — it lives in the west
# workspace, its slots come from a devicetree overlay, the disk-backed flash
# driver is an out-of-tree module, and the rest is Kconfig.
# The application needs the same treatment when a bootloader sits under it:
# CONFIG_BOOTLOADER_MCUBOOT links it at the slot's offset and has west sign
# it, and it can only know that offset from the same devicetree overlay the
# bootloader used. Empty when the application boots on its own.
IB_ZEPHYR_APP_OVERLAY ?= ""
IB_ZEPHYR_APP_CONF ?= ""
IB_ZEPHYR_APP_MODULES ?= ""

# Left empty rather than defaulted to ${IB_TARGET}/${IB_ZEPHYR_BOOT_APP}.
# zephyr.bbclass fills this in for MCUboot, from an anonymous python function
# that runs after every recipe is parsed — so a ?= here would already have
# claimed the variable by the time it looked, and the bootloader would be
# built from a directory under zephyr/usr that does not exist. The fallback
# for a bootloader that IS an application under zephyr/usr is applied in
# do_build, where it can be, and where it is visible.
IB_ZEPHYR_BOOT_SRC ?= ""
IB_ZEPHYR_BOOT_OVERLAY ?= ""
IB_ZEPHYR_BOOT_CONF ?= ""
IB_ZEPHYR_BOOT_MODULES ?= ""

# The west workspace root (zephyr/), its venv, and the board definitions
# from the meta-zephyr layer.
IB_ZEPHYR_WORKSPACE ?= "${IB_DIR}/zephyr"
IB_ZEPHYR_WEST ?= "${IB_ZEPHYR_WORKSPACE}/.venv/bin/west"
IB_ZEPHYR_BOARD ?= "ib_${IB_PLATFORM}"
IB_ZEPHYR_BOARD_ROOT ?= "${IB_DIR}/build/meta-zephyr/recipes-zephyr/zephyr/files"


# Build output, kept under IB_TARGET/build like linux/usr does. bsp-zephyr
# reads IB_ZEPHYR_IMAGE from here.
IB_ZEPHYR_BUILD_DIR ?= "${IB_TARGET}/build/${IB_ZEPHYR_APP}"
IB_ZEPHYR_BOOT_BUILD_DIR ?= "${IB_TARGET}/build/${IB_ZEPHYR_BOOT_APP}"

COMPATIBLE_PLATFORM = "virt64"

do_configure[noexec] = "1"

# zephyr/usr is versioned source, not a fetched component: there is no
# upstream tree to regenerate it from, and letting the attach machinery
# run would overwrite it.
do_attach_infrabase[noexec] = "1"


# MCUboot's source — and the AArch64 series this tree carries against it —
# belongs to mcuboot_2.4.0.bb, which fetches, patches and attaches it into
# the west workspace. Depend on that attach: west resolves the module from
# the workspace, so the tree has to be patched before any image is built,
# whether or not this build is the one that boots MCUboot.
do_build[depends] += "mcuboot:do_attach_infrabase"

do_build[nostamp] = "1"
do_build () {

	if [ ! -x "${IB_ZEPHYR_WEST}" ]; then
		bbfatal "No west at ${IB_ZEPHYR_WEST}.\n\nThe Zephyr workspace is not set up. From ${IB_ZEPHYR_WORKSPACE}:\n\n    python3 -m venv .venv && . .venv/bin/activate\n    pip install west && west init -l zephyr && west update\n    pip install -r zephyr/scripts/requirements.txt\n    west zephyr-export && west sdk install -t aarch64-zephyr-elf"
	fi

	if [ ! -f "${IB_TARGET}/${IB_ZEPHYR_APP}/CMakeLists.txt" ]; then
		bbfatal "No application at ${IB_TARGET}/${IB_ZEPHYR_APP} (set IB_ZEPHYR_APP to one of: $(cd ${IB_TARGET} 2>/dev/null && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' '))"
	fi

	bbplain "Building Zephyr application '${IB_ZEPHYR_APP}' for ${IB_ZEPHYR_BOARD}"

	# west resolves the workspace from the working directory (.west/), so
	# run from the workspace root rather than passing it around.
	# Same one-at-a-time assembly as the boot image below, and for the same
	# reason: west takes an empty -D value as a real argument.
	app_args="-DBOARD_ROOT=${IB_ZEPHYR_BOARD_ROOT}"
	[ -n "${IB_ZEPHYR_APP_OVERLAY}" ] && \
		app_args="$app_args -DEXTRA_DTC_OVERLAY_FILE=${IB_ZEPHYR_APP_OVERLAY}"
	[ -n "${IB_ZEPHYR_APP_CONF}" ] && \
		app_args="$app_args -DEXTRA_CONF_FILE=${IB_ZEPHYR_APP_CONF}"
	[ -n "${IB_ZEPHYR_APP_MODULES}" ] && \
		app_args="$app_args -DZEPHYR_EXTRA_MODULES=${IB_ZEPHYR_APP_MODULES}"

	cd ${IB_ZEPHYR_WORKSPACE}
	${IB_ZEPHYR_WEST} build \
		-b ${IB_ZEPHYR_BOARD} \
		-d ${IB_ZEPHYR_BUILD_DIR} \
		${IB_TARGET}/${IB_ZEPHYR_APP} \
		-- $app_args

	if [ ! -f "${IB_ZEPHYR_BUILD_DIR}/zephyr/zephyr.bin" ]; then
		bbfatal "west build produced no zephyr.bin in ${IB_ZEPHYR_BUILD_DIR}"
	fi

	# The pre-application image, when the chain has one. Same board, same
	# west invocation, its own build directory — two independent systems,
	# not two configurations of one.
	if [ -n "${IB_ZEPHYR_BOOT_APP}" ]; then
		# Unset means the bootloader is an application under zephyr/usr
		# like any other, named by IB_ZEPHYR_BOOT_APP. MCUboot is not —
		# it lives in the west workspace — which is why zephyr.bbclass
		# sets this for it.
		boot_src="${IB_ZEPHYR_BOOT_SRC}"
		[ -n "$boot_src" ] || boot_src="${IB_TARGET}/${IB_ZEPHYR_BOOT_APP}"

		if [ ! -f "$boot_src/CMakeLists.txt" ]; then
			bbfatal "No application at $boot_src (IB_ZEPHYR_BOOT_SRC, for IB_ZEPHYR_BOOT_APP='${IB_ZEPHYR_BOOT_APP}')"
		fi

		bbplain "Building Zephyr boot image '${IB_ZEPHYR_BOOT_APP}' for ${IB_ZEPHYR_BOARD}"

		# Built one -D at a time rather than inline: west takes the empty
		# string as a real argument, so an unset overlay would become
		# -DEXTRA_DTC_OVERLAY_FILE= and cmake would look for a file
		# called "".
		boot_args="-DBOARD_ROOT=${IB_ZEPHYR_BOARD_ROOT}"
		[ -n "${IB_ZEPHYR_BOOT_OVERLAY}" ] && \
			boot_args="$boot_args -DEXTRA_DTC_OVERLAY_FILE=${IB_ZEPHYR_BOOT_OVERLAY}"
		[ -n "${IB_ZEPHYR_BOOT_CONF}" ] && \
			boot_args="$boot_args -DEXTRA_CONF_FILE=${IB_ZEPHYR_BOOT_CONF}"
		[ -n "${IB_ZEPHYR_BOOT_MODULES}" ] && \
			boot_args="$boot_args -DZEPHYR_EXTRA_MODULES=${IB_ZEPHYR_BOOT_MODULES}"

		cd ${IB_ZEPHYR_WORKSPACE}
		${IB_ZEPHYR_WEST} build \
			-b ${IB_ZEPHYR_BOARD} \
			-d ${IB_ZEPHYR_BOOT_BUILD_DIR} \
			$boot_src \
			-- $boot_args

		if [ ! -f "${IB_ZEPHYR_BOOT_BUILD_DIR}/zephyr/zephyr.bin" ]; then
			bbfatal "west build produced no zephyr.bin in ${IB_ZEPHYR_BOOT_BUILD_DIR}"
		fi
	fi
}
addtask do_build

# No do_deploy: a Zephyr image is not installed into a rootfs, it *is* the
# system. bsp-zephyr picks the binary up through IB_ZEPHYR_IMAGE and puts
# it in the ITB.

do_clean[nostamp] = "1"
do_clean () {
	rm -rf ${IB_TARGET}/build
	rm -f ${TMPDIR}/stamps/usr-zephyr*
}
addtask do_clean
