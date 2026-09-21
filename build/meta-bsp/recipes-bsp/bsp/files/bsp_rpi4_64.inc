# Copyright (c) 2025-2026 EDGEMTech SA

# Deployment on RPi4 (64-bit) platform.
#
# The Raspberry Pi has no separate firmware image to assemble, so there is
# no __do_platform_boot_chain here: the ATF artefact (bl31.bin) is a plain
# file on the FAT boot partition, and p1 only exists once the deploy has
# mounted the storage. Both chains are therefore handled below, in
# __do_platform_deploy.

require bsp_arm_common.inc

def __do_platform_deploy(d):

    import os
    from bb.process import run

    print("Platform " + d.getVar('IB_PLATFORM'))

    filedirname = d.getVar('FILE_DIRNAME')
    dst = d.getVar('IB_FILESYSTEM_PATH')
    uboot_path = d.getVar('IB_UBOOT_PATH')
    chain = d.getVar('IB_BOOT_CHAIN') or "uboot"

    run(f"cp -r {filedirname}/../bsp/rpi4/* {dst}/p1")

    # bsp/rpi4/config.txt is shared with the 32-bit BSP and deliberately holds
    # no arm_64bit/kernel setting; append the 64-bit half of the chain.
    # FILE_DIRNAME is the *recipe's* directory (recipes-bsp/linux), not this
    # include's — hence the ../bsp hop, as in the copy above.
    run(f"cat {filedirname}/../bsp/files/config_rpi4_arm64.txt >> {dst}/p1/config.txt")

    # ATF chain: BL31 replaces the GPU firmware's armstub. It is loaded at
    # address 0, stays resident as the EL3 monitor and hands over at EL2 to
    # whatever the firmware loaded as kernel8.img — our U-Boot, unchanged.
    # OP-TEE is not an option on this SoC; see IB_BOOT_CHAINS_SUPPORTED in
    # build/conf/local.conf.
    if d.getVar('IB_CHAIN_HAS_ATF'):
        atf_plat = d.getVar('IB_ATF_PLAT') or "rpi4"
        bl31 = os.path.join(d.getVar('IB_ATF_PATH'), "build", atf_plat, "release", "bl31.bin")
        if not os.path.isfile(bl31):
            bb.fatal(bl31 + " is missing — has atf:do_build run?")
        run(f"cp {bl31} {dst}/p1/bl31.bin")
        run(f"cat {filedirname}/../bsp/files/config_rpi4_atf.txt >> {dst}/p1/config.txt")

    run(f"cp {uboot_path}/u-boot.bin {dst}/p1/kernel8.img")

    __deploy_arm_common(d)
