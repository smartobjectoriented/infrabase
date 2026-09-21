# Copyright (c) 2026 EDGEMTech SA
# SPDX-License-Identifier: Apache-2.0

if(CONFIG_FLASH_DISK)
  zephyr_library()
  zephyr_library_sources(drivers/flash/flash_disk.c)
endif()
