
.. _linux_usr:


Linux user applications (usr)
*****************************

In addition to the contents defined in the *rootfs*, additional applications can be built and deployed in the
``linux/usr/`` directory. Such applications are specific to the agency and do not belong to any external packages.

Deployment in the rootfs
========================

All applications and files which need to be deployed in the rootfs must be first installed
in the ``linux/usr/build/deploy`` directory. To do so, the current approach is to edit
the ``usr-linux`` recipe adding the *install* command, for example:

.. code:: bash

   usr_do_install_file_root "${IB_TARGET}/build/src/examples/hello"

This command will copy the ``hello`` binary to ``build/deploy/root``, which ends up in the
``root/`` home directory of the target rootfs. Companion helpers exist for a whole directory
(``usr_do_install_directory_root``) and for an arbitrary destination
(``usr_do_install_file_dir``).


Development of modules and deployment
=====================================

Out-of-tree kernel modules are compiled from ``linux/usr/src/modules/``, whose ``Makefile``
selects the module set according to ``IB_PLATFORM`` as defined in ``build/conf/local.conf``.
They are built against the attached kernel tree (``linux/linux``) with the kernel's own cross
compiler, so the kernel must have been built first.

The resulting ``.ko`` files are deployed in the ``root/`` home directory of the target
``rootfs``. The ``insmod`` application can then be used from the *shell* in order to load the
module into the kernel.

A module can be helpful for testing purposes, for example to test kernel functionalities.

Quick rebuild without bitbake
=============================

Going through bitbake for every edit is slow. ``makeusr.sh`` reproduces what the recipe does
in ``do_build`` — CMake, ``make``, and the kernel modules — and deploys locally into
``linux/usr/build/deploy``:

.. code-block:: bash

   $ cd linux/usr && makeusr.sh

It requires the buildroot toolchain to have been built once, since it takes the CMake
toolchain file from ``linux/rootfs/host``. Run ``makeusr.sh -h`` for the options (build type,
platform, skipping the modules, cleaning). Use ``deploy.sh usr-linux`` when you want the
result in the target rootfs.


