/* Same probe, but sleeping instead of spinning: this makes the idle
 * thread run and the core execute WFI between ticks.
 */

#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

int main(void)
{
	printk("tick-probe(sleep): start, uptime=%lld\n", k_uptime_get());

	for (int i = 0; i < 10; i++) {
		k_msleep(200);
		printk("sleep %d: uptime=%lld ticks=%u\n",
		       i, k_uptime_get(), (unsigned) sys_clock_tick_get_32());
	}

	printk("tick-probe(sleep): done\n");
	return 0;
}
