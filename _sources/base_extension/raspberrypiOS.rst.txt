.. _raspberrypiOS:

 
Raspberry Pi OS
###############

Introduction
************ 
The `Raspberry Pi OS <https://www.raspberrypi.com/software/>`__ is a full system image containing the whole system to boot on the RPi4. It is based on Ubuntu and comes in many flavors (headless, 64bit, desktop, ...).

Usability in the Infrabase framework
************************************
The Raspberry Pi OS is usefull to quickly deploy a functionnal system on the board. Here is an overview of the pros and cons 

Pros:

 - Uses config.txt to configure the system at boot time.
 - APT compatible.
 - Zero effort to flash.
 
Cons:

 - No rootfs customization
 - Needs the raspberry linux kernel.


In the end, it is nice to have it for quick tests, but becomes quickly limitating when we want to customize the environnement a bit.

