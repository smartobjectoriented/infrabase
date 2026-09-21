# Copyright (c) 2026 EDGEMTech SA
# SPDX-License-Identifier: Apache-2.0
#
# `west build -t run` mirrors the QEMU line in scripts/st.sh, minus the
# virtio disk / net devices that only the Linux and SO3 boot modes use.

set(SUPPORTED_EMU_PLATFORMS qemu)
set(QEMU_BINARY_SUFFIX aarch64)

set(QEMU_CPU_TYPE cortex-a72)
set(QEMU_MACH virt,gic-version=2)

set(QEMU_BOARD_FLAGS
  -cpu ${QEMU_CPU_TYPE}
  -machine ${QEMU_MACH}
  -m 1024
  -smp 4
  )

include(${ZEPHYR_BASE}/boards/common/qemu.board.cmake)
