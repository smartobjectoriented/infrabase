/*
 * Copyright (c) 2026 EDGEMTech SA
 * SPDX-License-Identifier: Apache-2.0
 *
 * Stand-in for MCUboot, for the boot-dispatch mock-up.
 *
 * The target architecture is
 *
 *     ATF -> OP-TEE -> U-Boot -> MCUboot -> Zephyr
 *
 * so that a developer exercises the same boot path the final hardware
 * uses. MCUboot has no aarch64 support today (boot/zephyr/CMakeLists.txt
 * selects on CONFIG_ARM, which is 32-bit ARM; Cortex-A falls through to
 * arch/default.c, a bare function-pointer jump with no MMU or cache
 * teardown), so porting it is real work.
 *
 * This image exists to derisk everything *around* that port: that the FC
 * can flag a boot target from Linux, that U-Boot picks the flag up on the
 * next reset and dispatches, and that the Zephyr capsule is what comes
 * up. It occupies MCUboot's slot in the chain and does nothing else — it
 * verifies no signature, owns no slots, chain-loads nothing.
 *
 * Replace it with the real thing once the aarch64 port exists and the
 * slot storage is decided (and that decision has to mirror the final
 * hardware, or the fidelity this whole exercise buys is lost).
 */

#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

int main(void)
{
	printk("\n");
	printk("=====================================================\n");
	printk(" MCUboot stand-in — boot dispatch mock-up\n");
	printk("=====================================================\n");
	printk(" U-Boot reached this image, so the dispatch worked:\n");
	printk("   a boot target was written to /e1c/boot.env on p2\n");
	printk("   U-Boot imported it and branched here instead of\n");
	printk("   the default target\n");
	printk("\n");
	printk(" The real MCUboot would now verify a signed image in\n");
	printk(" its slot and jump to it. This one just says so.\n");
	printk("=====================================================\n");

	while (1) {
		k_sleep(K_SECONDS(5));
	}

	return 0;
}
