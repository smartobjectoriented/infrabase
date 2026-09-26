#!/bin/bash

# Copyright (c) 2025-2026 EDGEMTech SA

# Release banner, once per invocation (see scripts/common/banner.sh).
. "$(cd "$(dirname "$(command -v -- "$0")")" && pwd)/common/banner.sh"

# Resolve project root from this script's own location, cd there, and
# source env.sh — prompting the user first if the parent shell points
# at a different tree. Every relative path below (filesystem/...,
# build/conf/local.conf) is anchored on that root. See
# scripts/common/setup_env.sh.

# Handled before setup_env.sh: printing the help should not trigger the
# tree-switch prompt that sourcing the environment can raise.

case "$1" in
    -h|--help)
        echo "Usage: $(basename "$0") [-d] [qemu-option]"
        echo "  Run the deployed image under QEMU. Headless by default: the"
        echo "  serial console is multiplexed onto stdio."
        echo "    -d   graphical — open an SDL window with a virtio GPU and"
        echo "         virtio keyboard/mouse attached to the guest"
        exit 0
        ;;
esac

. "$(cd "$(dirname "$(command -v -- "$0")")" && pwd)/common/setup_env.sh"

QEMU_AUDIO_DRV="none"
GDB_PORT_BASE=1234

# Parse our own options out of the argument list before what is left is
# forwarded to QEMU as USR_OPTION.

WITH_DISPLAY=0
POSARGS=()
for _a in "$@"; do
    case "$_a" in
        -d) WITH_DISPLAY=1 ;;
        *)  POSARGS+=("$_a") ;;
    esac
done
set -- "${POSARGS[@]}"
USR_OPTION=$1

# Display mode. Headless by default: serial only, no window. With -d, present
# the guest on a virtio GPU in an SDL window and give it virtio input devices
# — the console stays on stdio either way, so a graphical run is still
# scriptable. This replaces the former separate stg.sh.

if [ "$WITH_DISPLAY" = "1" ]; then
    DISPLAY_OPT="-device virtio-gpu-pci -device virtio-keyboard-pci \
		-device virtio-mouse-pci -display sdl"
else
    DISPLAY_OPT="-display none"
fi

# QEMU_BIN is selected per IB_PLATFORM below (qemu-system-aarch64 for
# virt64, qemu-system-arm for virt32).

# Count every emulator, whatever the architecture: "qemu-system-arm" does
# not match "qemu-system-aarch64", so a 64-bit instance used to go
# uncounted and a second run reused its MAC address and GDB port.

N_QEMU_INSTANCES=`ps -A | grep qemu-system | wc -l`

launch_qemu() {
    QEMU_MAC_ADDR="$(printf 'DE:AD:BE:EF:%02X:%02X\n' $((N_QEMU_INSTANCES)) $((N_QEMU_INSTANCES)))"

    GDB_PORT=$((${GDB_PORT_BASE} + ${N_QEMU_INSTANCES}))

    echo -e "\033[01;36mMAC addr: " ${QEMU_MAC_ADDR} "\033[0;37m"
    echo -e "\033[01;36mGDB port: " ${GDB_PORT} "\033[0;37m"

    # Read a plain (non-override) assignment out of the configuration.
    # Reads local.conf THEN site.conf, in the order bitbake.conf includes
    # them, and takes the LAST match: bitbake is last-assignment-wins, so a
    # site.conf override has to win here too — otherwise the launcher would
    # boot a machine differently from how it was built. (An image build may
    # likewise append its own value after the "?=" default.)
    conf_value() {
        cat build/conf/local.conf build/conf/site.conf 2>/dev/null \
            | grep -E "^$1[[:space:]]*[?:]?=" \
            | grep -v "^$1:" \
            | tail -1 | sed -n 's/.*"\([^"]*\)".*/\1/p'
    }

    IB_PLATFORM="$(conf_value IB_PLATFORM)"

    # One guest per storage image.
    #
    # Every instance attaches filesystem/sdcard.img.<platform> with
    # file.locking=off, so a second guest on the SAME image writes into the
    # filesystem the first one is already writing to — silently.
    #
    # Scoped to the image rather than to QEMU as a whole, on purpose: two
    # platforms use two images and may legitimately run side by side, which
    # is what the per-instance MAC / GDB port offsets above are for. Only the
    # same-image case is refused.
    #
    # The pgrep pattern deliberately requires a trailing space after the
    # binary name so it cannot match this script's own command line.
    _st_img="filesystem/sdcard.img.${IB_PLATFORM}"
    _st_busy=""
    for _p in $(pgrep -f 'qemu-system-[a-z0-9]+ ' 2>/dev/null); do
        tr '\0' ' ' < /proc/$_p/cmdline 2>/dev/null | grep -Fq -- "$_st_img" || continue
        # The same spelling in two trees is not the same file: every tree
        # names its image "filesystem/sdcard.img.<plat>" and QEMU records
        # that relative path verbatim. Resolve it through the guest's own
        # cwd before deciding, or a guest in a sibling tree would block us.
        [ "$(readlink -f /proc/$_p/cwd 2>/dev/null)/$_st_img" = "$PWD/$_st_img" ] \
            && _st_busy="${_st_busy}${_p} "
    done
    if [ -n "${_st_busy}" ]; then
        printf "Error: a QEMU guest is already using %s (pid %s).\n" \
            "$_st_img" "${_st_busy% }" >&2
        printf "       Two guests on one image corrupt it. Quit that one first:\n" >&2
        printf "       Ctrl-A x in its console, or kill %s\n" "${_st_busy% }" >&2
        exit 1
    fi

    if [ "$IB_PLATFORM" == "virt64" ]; then
    QEMU_BIN="$IB_ROOT_DIR/qemu/build/qemu-system-aarch64"
    echo Starting on virt64
    # User-mode (slirp) networking: QEMU plays DHCP + DNS + NAT internally, so
    # the guest gets 10.0.2.15 immediately and NetworkManager-wait-online
    # succeeds in <1 s instead of timing out at 60 s as it did with tap+host
    # bridge that had no DHCP server. hostfwd exposes guest SSH on host
    # port 2222 for convenience. Trade-off: guest is NAT'd, no LAN visibility.
    # Bonus: no sudo needed (no tap device creation), so QEMU artefacts stay
    # owned by the regular user across runs.
    #
    # How the machine starts is not worked out here: the build knows the boot
    # chain, so the build states it, in filesystem/boot.conf written by
    # bsp.bbclass:do_deploy_boot_chain -> bsp_virt64.inc.
    #
    # It used to be guessed from which artefacts were lying in filesystem/
    # plus an IB_HYPERVISOR read out of local.conf. Both were guesses at
    # something the build already knows: the chain is normalised at parse
    # time by base.bbclass:ib_normalize_boot_axes, a layer may declare its
    # own, and the legacy "full" alias expands to a hypervisor that appears
    # in no .conf file at all. None of that is visible to a shell reading
    # local.conf.
    #
    #   "uboot", "mcuboot"   the first stage is on the card, in the raw area
    #                        ahead of p1, and the machine's boot ROM reads it
    #                        from there (bootrom-* machine properties; see
    #                        virt_bootrom_setup() in qemu/hw/arm/virt.c).
    #   the ATF chains       BL1 executes in place from address 0, so
    #                        flash0.img is pflash-mapped and EL3 is exposed.

    if [ ! -f filesystem/boot.conf ]; then
        echo "st.sh: no filesystem/boot.conf — run deploy.sh first" >&2
        return 1
    fi
    . ./filesystem/boot.conf

    echo "Boot chain: ${IB_QEMU_CHAIN}"
    MACHINE_OPT="-M ${IB_QEMU_MACHINE}"
    BOOT_OPT="${IB_QEMU_BOOT}"

    # virtio-mmio in modern (version 2) mode. QEMU defaults force-legacy=on,
    # which presents version 1, and Zephyr's virtio_mmio driver implements
    # only the modern interface — it refuses the device with "Invalid version
    # 1", so a bootloader never gets the disk its slots live on. U-Boot and
    # Linux both speak either version, so this costs the other
    # configurations nothing.
    ${QEMU_BIN} $@ ${USR_OPTION} \
		-smp 4  \
		-chardev stdio,id=char0,mux=on,signal=off \
		-mon chardev=char0 \
		-serial chardev:char0 \
		${MACHINE_OPT} -cpu cortex-a72  \
		-global virtio-mmio.force-legacy=false \
		${BOOT_OPT} \
		-device virtio-blk-device,drive=hd0 \
		-drive if=none,file=filesystem/sdcard.img.virt64,id=hd0,format=raw,file.locking=off \
		-m 1024 \
		${DISPLAY_OPT} \
		-netdev user,id=n1,hostfwd=tcp::2222-:22 \
		-device virtio-net-device,netdev=n1,mac=${QEMU_MAC_ADDR} \
        	-gdb tcp::${GDB_PORT}
	fi

    if [ "$IB_PLATFORM" == "virt32" ]; then
    QEMU_BIN="$IB_ROOT_DIR/qemu/build/qemu-system-arm"
    echo Starting on virt32
    # 32-bit ARM virt: U-Boot is loaded directly with -kernel (no ATF/flash
    # chain on this platform) and cortex-a15 matches the virt32 kernel build.
    # Serial console is muxed onto stdio and networking is slirp, exactly as
    # on virt64. Without this branch a virt32 tree ran nothing at all.
    ${QEMU_BIN} $@ ${USR_OPTION} \
		-smp 4  \
		-chardev stdio,id=char0,mux=on,signal=off \
		-mon chardev=char0 \
		-serial chardev:char0 \
		-M virt -cpu cortex-a15 \
		-kernel u-boot/u-boot \
		-device virtio-blk-device,drive=hd0 \
		-drive if=none,file=filesystem/sdcard.img.virt32,id=hd0,format=raw,file.locking=off \
		-m 1024 \
		${DISPLAY_OPT} \
		-netdev user,id=n1,hostfwd=tcp::2222-:22 \
		-device virtio-net-device,netdev=n1,mac=${QEMU_MAC_ADDR} \
        	-gdb tcp::${GDB_PORT}
	fi

    QEMU_RESULT=$?
}

launch_qemu
