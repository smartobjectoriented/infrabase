
Glossary
########

.. glossary::

   Standard script
      A script which is out of the scope of bitbake. They live in ``scripts/`` at the root of
      *Infrabase* and are on your ``PATH`` once ``env.sh`` is sourced, so they can be invoked
      from anywhere in the tree. ``build.sh``, ``deploy.sh``, ``st.sh`` and ``mount.sh`` are
      the ones you use daily.

   Platform
      The target machine, selected by ``IB_PLATFORM`` in ``build/conf/local.conf``
      (*virt64*, *rpi4_64*, …). BitBake calls the same notion a *machine*, and the value is
      used as an override to scope variables per target.

   BSP
      *Board Support Package*. The recipe that pulls a whole system together for a platform
      (``bsp-linux``), as opposed to a *component* recipe (``linux``, ``uboot``, …) which
      builds only itself.

   Attached tree
      A component's source tree, copied to the root of *Infrabase* by the
      ``do_attach_infrabase`` task (``linux/linux``, ``u-boot``, ``qemu``, …) so development
      happens outside the ``build/tmp`` directory that bitbake manages. Attached trees are not
      in git: your changes there are preserved as a *patchset*.

   Patchset
      The collection of patches applied to a component during ``do_patch``, tracked in the
      recipe's ``files/`` directory and listed by an ``.inc`` file. Regenerated from an
      attached tree with the ``do_updiff`` task.
