# Copyright (c) 2026 EDGEMTech SA

# Class for the Zephyr environment in infrabase

# The west workspace root. Everything Zephyr lives under it: the Zephyr tree
# itself at zephyr/zephyr, the modules and the bootloader west fetches, and
# this tree's applications at zephyr/usr.
IB_ZEPHYR_WORKSPACE = "${IB_DIR}/zephyr"
IB_ZEPHYR_PATH = "${IB_ZEPHYR_WORKSPACE}/zephyr"

# The Zephyr tree the workspace is built from.
#
# Pinned for the same reason mcuboot_2.4.0.bb pins its SRCREV: west fetches
# into a gitignored directory, so nothing in the repo would otherwise record
# which Zephyr everything here was verified against, and a fresh workspace
# would take whatever main happened to be that day. The two have to stay in
# step with each other — MCUboot's revision is the one zephyr/west.yml names
# at THIS revision of Zephyr.
#
# Not a SRC_URI: the workspace is west's, not bitbake's, and west resolves the
# modules from the manifest inside this tree. Read by the CI bootstrap, which
# has no workspace to start from.
IB_ZEPHYR_REPO ?= "https://github.com/zephyrproject-rtos/zephyr.git"
IB_ZEPHYR_SRCREV ?= "4ff80a5ccdf7b9f4724b08ec393dc18b583b0b74"

# Where the Zephyr SDK is, when it is not in the CMake package registry.
#
# Two steps are needed and neither is enough alone: env.sh names the variable
# in BB_ENV_PASSTHROUGH_ADDITIONS so bitbake's filtered environment lets it
# through into the datastore, and the export flag below is what puts it in the
# task's own environment. Without the flag the value is visible to recipes and
# invisible to west, and Zephyr's FindZephyr-sdk.cmake fails with nothing but
# a find_package error naming Zephyr-sdkConfig.cmake.
#
# Flagged only when it has a value: `setup.sh -c` registers the SDK per-user,
# and a tree relying on that registry must not have an empty variable exported
# over it. Setting ZEPHYR_SDK_INSTALL_DIR in the environment is what the build
# container does — the SDK is in the image, outside any user's home.
python () {
    if d.getVar('ZEPHYR_SDK_INSTALL_DIR'):
        d.setVarFlag('ZEPHYR_SDK_INSTALL_DIR', 'export', '1')
}

# The Zephyr board this platform builds for. Declared here rather than in a
# recipe because the board names the devicetree overlay and Kconfig fragment
# a build carries, and more than one recipe needs to find them.
IB_ZEPHYR_BOARD ?= "ib_${IB_PLATFORM}"

# MCUboot, when a chain uses it. The recipe (meta-zephyr/recipes-zephyr/
# mcuboot) owns the source and the patch series; these are what a build needs
# alongside it — the Zephyr pair for this board, and the out-of-tree module
# giving MCUboot its slots on the disk.
#
# Named after the board, which is Zephyr's own convention for the pair
# (boards/<board>.conf and boards/<board>.overlay inside an application), so
# a second board is a second pair of files rather than a second variable.
IB_MCUBOOT_LAYER ?= "${IB_DIR}/build/meta-zephyr/recipes-zephyr"
IB_MCUBOOT_SRC ?= "${IB_ZEPHYR_WORKSPACE}/bootloader/mcuboot/boot/zephyr"
# A shared overlay plus one per side: the shared file describes the slots and
# where a RAM-loaded image goes, -mcuboot maps that destination into the
# bootloader, and -payload links the application into it. west takes a
# semicolon-separated list.
IB_MCUBOOT_OVERLAY ?= "${IB_MCUBOOT_LAYER}/mcuboot/conf/${IB_ZEPHYR_BOARD}.overlay;${IB_MCUBOOT_LAYER}/mcuboot/conf/${IB_ZEPHYR_BOARD}-mcuboot.overlay"
IB_MCUBOOT_PAYLOAD_OVERLAY ?= "${IB_MCUBOOT_LAYER}/mcuboot/conf/${IB_ZEPHYR_BOARD}.overlay;${IB_MCUBOOT_LAYER}/mcuboot/conf/${IB_ZEPHYR_BOARD}-payload.overlay"
IB_MCUBOOT_CONF ?= "${IB_MCUBOOT_LAYER}/mcuboot/conf/${IB_ZEPHYR_BOARD}.conf"
IB_MCUBOOT_MODULES ?= "${IB_MCUBOOT_LAYER}/flash-disk"

# What an application needs to boot under that MCUboot: the same overlay, so
# it links at the same slot, plus CONFIG_BOOTLOADER_MCUBOOT.
IB_MCUBOOT_PAYLOAD_CONF ?= "${IB_MCUBOOT_LAYER}/mcuboot/conf/${IB_ZEPHYR_BOARD}-payload.conf"


# Naming the first image is the whole configuration.
#
# A tree that wants MCUboot says so once — IB_ZEPHYR_BOOT_APP = "mcuboot" —
# and everything else follows: where its sources are, which overlays and
# Kconfig fragments the bootloader takes, and which ones the application it
# boots takes instead. All of that is stated above already, and repeating it
# per configuration only creates places for the two to disagree.
#
# Anonymous python rather than seven ?= with an inline conditional: the
# condition is one fact about the build, and written once it reads as the
# sentence it is.
#
# ?= semantics are preserved by hand — an explicit value always wins. That is
# what lets a tree take MCUboot and still point one of these somewhere else,
# say at an overlay of its own, without having to restate the other six.
python () {
    if (d.getVar('IB_ZEPHYR_BOOT_APP') or "") != "mcuboot":
        return

    # The bootloader, then the application that boots under it. The
    # application's are not optional extras: CONFIG_BOOTLOADER_MCUBOOT links
    # it at the slot's offset and has west sign it, and it can only know that
    # offset from the same devicetree the bootloader used.
    for var, source in (
            ('IB_ZEPHYR_BOOT_SRC',     'IB_MCUBOOT_SRC'),
            ('IB_ZEPHYR_BOOT_OVERLAY', 'IB_MCUBOOT_OVERLAY'),
            ('IB_ZEPHYR_BOOT_CONF',    'IB_MCUBOOT_CONF'),
            ('IB_ZEPHYR_BOOT_MODULES', 'IB_MCUBOOT_MODULES'),
            ('IB_ZEPHYR_APP_OVERLAY',  'IB_MCUBOOT_PAYLOAD_OVERLAY'),
            ('IB_ZEPHYR_APP_CONF',     'IB_MCUBOOT_PAYLOAD_CONF'),
            ('IB_ZEPHYR_APP_MODULES',  'IB_MCUBOOT_MODULES'),
    ):
        if not d.getVar(var):
            d.setVar(var, d.getVar(source))
}
