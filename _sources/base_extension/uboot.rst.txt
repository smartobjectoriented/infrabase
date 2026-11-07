.. _uboot:


U-Boot modifications
####################
In order to support the boot from the ITB while using the DTB prepared by the RPi bootloader, we needed to modify U-Boot.
The original could only boot from one or the other method.

The RPi bootloader patches the DTB using the overlays specified in the config.txt file. When U-Boot takes the hand, the env variable ``fdt_addr`` is set to the address of the modified DTB.
The fix was to add a configuration ``CONFIG_USE_RPI4_DTB_WITH_FIT`` to be able to bypass the DTB retrieval in the FIT image (ITB).
We also need U-Boot to fill it with initrd information for Linux to be able to mount it. 

All the modifications are done in ``common/bootm.c``:

 * line 283: If we use the new config, U-Boot sets its internal ``fdt_addr`` and ``fdt_len`` not by reading the ITB and parsinbg the DTB, but by reading the ``fdtaddr`` variable.
 * line 762: With the new configuration, it ignores the state check when configuring the DTB, it allow to configure it even without a DTB in the FIT image.


Further improvements
####################
These modifications where implemented in a quick way to be able to use the custom DTB. However, it lacks some checks made by the classical path. 
It is usable but still need some refining in how we handle the DTB loading.

