/*
 * Copyright (c) 2026 EDGEMTech SA
 * SPDX-License-Identifier: Apache-2.0
 *
 * Hello world for infrabase targets, with the watchdog kick the verdin
 * needs to stay alive.
 *
 * This used to be a patch against Zephyr's own samples/hello_world
 * (zephyr/patches/0003-sample-feed-WD-to-avoid-a-reboot.patch). That was
 * the wrong place twice over: the NXP U-Boot arming the watchdog is a
 * property of our platform, not of an upstream sample, and the patch made
 * hello_world reference DT_ALIAS(watchdog0) unconditionally, which breaks
 * the build on every board that has no such alias — qemu_cortex_a53
 * included, where it fails with
 *
 *     '__device_dts_ord_DT_N_ALIAS_watchdog0_ORD' undeclared
 *
 * Here the watchdog is optional at compile time, so the same application
 * builds for virt64 (no watchdog0) and for the verdin (wdog1), and the
 * Zephyr tree stays untouched.
 */

#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#if DT_HAS_ALIAS(watchdog0)
#include <zephyr/drivers/watchdog.h>

static const struct device *const wdt = DEVICE_DT_GET(DT_ALIAS(watchdog0));

/* 30 s window: the kick below runs every 5 s, so six missed kicks in a row
 * are needed before the SoC is reset. WDT_FLAG_RESET_SOC because a hung
 * application should take the board down, not just its own CPU. */
static struct wdt_timeout_cfg wdt_config = {
	.flags = WDT_FLAG_RESET_SOC,
	.window.min = 0,
	.window.max = 30000,
};

static int wdt_channel_id = -1;

static void watchdog_start(void)
{
	if (!device_is_ready(wdt)) {
		printk("watchdog0 not ready, running without it\n");
		return;
	}

	wdt_channel_id = wdt_install_timeout(wdt, &wdt_config);
	if (wdt_channel_id < 0) {
		printk("wdt_install_timeout failed (%d)\n", wdt_channel_id);
		return;
	}

	/* PAUSE_HALTED_BY_DBG so a breakpoint does not reset the board. */
	(void) wdt_setup(wdt, WDT_OPT_PAUSE_HALTED_BY_DBG);
}

static void watchdog_kick(void)
{
	if (wdt_channel_id >= 0) {
		(void) wdt_feed(wdt, wdt_channel_id);
	}
}
#else
static void watchdog_start(void) { }
static void watchdog_kick(void) { }
#endif /* DT_HAS_ALIAS(watchdog0) */

int main(void)
{
	watchdog_start();

	printk("Hello World! %s\n", CONFIG_BOARD_TARGET);

	while (1) {
		watchdog_kick();
		k_sleep(K_MSEC(5000));
	}

	/* Unreachable */
	return 0;
}
