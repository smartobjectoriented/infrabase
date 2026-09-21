/*
 * Copyright (c) 2026 EDGEMTech SA
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * A flash device backed by a window of a block device.
 *
 * MCUboot keeps its slots in a flash_map, and flash_map sits on the flash
 * API. A board whose only storage is a disk — virtio-blk under QEMU, eMMC on
 * the hardware — therefore cannot give MCUboot a slot at all. Zephyr ships
 * zephyr,flash-disk, but that goes the other way: it presents a flash
 * partition as a disk. This is the missing direction.
 *
 * What a disk does not have is erase. The flash API's contract is that a
 * read after erase returns erase-value, and that a write only clears bits;
 * callers align to erase-block-size and erase before writing. Both halves are
 * honoured here by writing erase-value across the range, which costs a pass
 * over the window but keeps every flash_map user correct without knowing
 * what is underneath. No bit-level AND is attempted on write: a disk
 * overwrites, and MCUboot never relies on the AND.
 */

#define DT_DRV_COMPAT edgemtech_flash_disk

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/flash.h>
#include <zephyr/storage/disk_access.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(flash_disk, CONFIG_FLASH_LOG_LEVEL);

struct flash_disk_config {
	const char *disk;
	off_t offset;			/* byte offset of the window in the disk */
	size_t size;			/* byte size of the window */
	uint32_t erase_block_size;
	uint32_t write_block_size;
	uint8_t erase_value;
	struct flash_pages_layout layout;
	struct flash_parameters params;
};

struct flash_disk_data {
	struct k_mutex lock;
	uint32_t sector_size;
	uint8_t *bounce;		/* one sector, for unaligned access */
};

static inline const struct flash_disk_config *cfg_of(const struct device *dev)
{
	return dev->config;
}

static bool in_window(const struct flash_disk_config *cfg, off_t off, size_t len)
{
	return off >= 0 && len <= cfg->size && (size_t)off <= cfg->size - len;
}

/* Read or write a byte range that need not be sector aligned, through a
 * scratch buffer. `wr` selects the direction; the two paths differ only
 * there, and keeping them in one function is what stops the alignment
 * arithmetic being written twice.
 *
 * Every sector is bounced, including whole aligned ones that could in
 * principle go straight through. The flash API makes no promise about the
 * caller's buffer, and the block layer under this one needs a very specific
 * kind: with CONFIG_MMU the virtqueue translates buffers with
 * k_mem_phys_addr(), which is only valid inside the kernel's linear RAM
 * mapping. Handing it anything else fails — MCUboot RAM-loading an image to
 * an address outside its own sram0 got -EIO from the first sector, because
 * that is exactly what the destination is. One memcpy per sector buys
 * "any buffer works", which is what a flash driver is supposed to offer.
 */
static int rw(const struct device *dev, off_t off, void *buf, size_t len, bool wr)
{
	const struct flash_disk_config *cfg = cfg_of(dev);
	struct flash_disk_data *data = dev->data;
	uint8_t *p = buf;
	int rc = 0;

	if (len == 0) {
		return 0;
	}
	if (!in_window(cfg, off, len)) {
		LOG_ERR("%s: [0x%lx,+0x%zx) outside the %zu-byte window",
			dev->name, (unsigned long)off, len, cfg->size);
		return -EINVAL;
	}

	off += cfg->offset;

	k_mutex_lock(&data->lock, K_FOREVER);

	while (len > 0) {
		uint32_t ssz = data->sector_size;
		uint32_t sector = (uint32_t)(off / ssz);
		uint32_t skew = (uint32_t)(off % ssz);
		size_t chunk = MIN(len, (size_t)(ssz - skew));

		if (wr && skew == 0 && chunk == ssz) {
			/* A whole sector is overwritten, so there is nothing
			 * worth reading first.
			 */
			memcpy(data->bounce, p, ssz);
			rc = disk_access_write(cfg->disk, data->bounce,
					       sector, 1);
		} else {
			rc = disk_access_read(cfg->disk, data->bounce, sector, 1);
			if (rc == 0) {
				if (wr) {
					memcpy(data->bounce + skew, p, chunk);
					rc = disk_access_write(cfg->disk,
							       data->bounce,
							       sector, 1);
				} else {
					memcpy(p, data->bounce + skew, chunk);
				}
			}
		}

		if (rc != 0) {
			LOG_ERR("%s: disk %s at sector %u failed: %d",
				dev->name, wr ? "write" : "read", sector, rc);
			break;
		}

		off += chunk;
		p += chunk;
		len -= chunk;
	}

	k_mutex_unlock(&data->lock);
	return rc;
}

static int flash_disk_read(const struct device *dev, off_t off, void *buf, size_t len)
{
	return rw(dev, off, buf, len, false);
}

static int flash_disk_write(const struct device *dev, off_t off, const void *buf, size_t len)
{
	const struct flash_disk_config *cfg = cfg_of(dev);

	if ((off % cfg->write_block_size) != 0 || (len % cfg->write_block_size) != 0) {
		LOG_ERR("%s: write [0x%lx,+0x%zx) is not %u-aligned",
			dev->name, (unsigned long)off, len, cfg->write_block_size);
		return -EINVAL;
	}

	return rw(dev, off, (void *)buf, len, true);
}

static int flash_disk_erase(const struct device *dev, off_t off, size_t len)
{
	const struct flash_disk_config *cfg = cfg_of(dev);
	struct flash_disk_data *data = dev->data;
	size_t done = 0;
	int rc = 0;

	if ((off % cfg->erase_block_size) != 0 || (len % cfg->erase_block_size) != 0) {
		LOG_ERR("%s: erase [0x%lx,+0x%zx) is not %u-aligned",
			dev->name, (unsigned long)off, len, cfg->erase_block_size);
		return -EINVAL;
	}

	/* A disk cannot erase, so spell the erased state out one sector at a
	 * time. The scratch buffer is already there for unaligned access.
	 */
	memset(data->bounce, cfg->erase_value, data->sector_size);

	while (done < len) {
		size_t chunk = MIN((size_t)data->sector_size, len - done);

		rc = rw(dev, off + done, data->bounce, chunk, true);
		if (rc != 0) {
			return rc;
		}
		done += chunk;
	}

	return 0;
}

static const struct flash_parameters *flash_disk_parameters(const struct device *dev)
{
	/* struct flash_parameters is const-qualified throughout, so it is
	 * built once per instance below rather than filled in here.
	 */
	return &cfg_of(dev)->params;
}

#if defined(CONFIG_FLASH_PAGE_LAYOUT)
static void flash_disk_pages(const struct device *dev,
			     const struct flash_pages_layout **layout,
			     size_t *layout_size)
{
	*layout = &cfg_of(dev)->layout;
	*layout_size = 1;
}
#endif

static int flash_disk_init(const struct device *dev)
{
	const struct flash_disk_config *cfg = cfg_of(dev);
	struct flash_disk_data *data = dev->data;
	uint32_t ssz = 0;
	int rc;

	k_mutex_init(&data->lock);

	rc = disk_access_init(cfg->disk);
	if (rc != 0) {
		LOG_ERR("%s: disk '%s' will not initialise: %d",
			dev->name, cfg->disk, rc);
		return rc;
	}

	rc = disk_access_ioctl(cfg->disk, DISK_IOCTL_GET_SECTOR_SIZE, &ssz);
	if (rc != 0 || ssz == 0) {
		LOG_ERR("%s: disk '%s' reports no sector size: %d",
			dev->name, cfg->disk, rc);
		return rc ? rc : -EIO;
	}

	/* The window has to land on sector boundaries, or every access would
	 * carry a partial sector and a read-modify-write for no reason. Say so
	 * now rather than corrupt a neighbour later.
	 */
	if ((cfg->offset % ssz) != 0 || (cfg->size % ssz) != 0) {
		LOG_ERR("%s: window [0x%lx,+0x%zx) is not aligned to the %u-byte sector",
			dev->name, (unsigned long)cfg->offset, cfg->size, ssz);
		return -EINVAL;
	}
	if (ssz > cfg->erase_block_size) {
		LOG_ERR("%s: sector %u is larger than the erase block %u",
			dev->name, ssz, cfg->erase_block_size);
		return -EINVAL;
	}

	data->sector_size = ssz;

	LOG_INF("%s: %zu bytes at +0x%lx of disk '%s' (%u-byte sectors)",
		dev->name, cfg->size, (unsigned long)cfg->offset, cfg->disk, ssz);

	return 0;
}

static DEVICE_API(flash, flash_disk_api) = {
	.read = flash_disk_read,
	.write = flash_disk_write,
	.erase = flash_disk_erase,
	.get_parameters = flash_disk_parameters,
#if defined(CONFIG_FLASH_PAGE_LAYOUT)
	.page_layout = flash_disk_pages,
#endif
};

#define FLASH_DISK_DEFINE(n)								\
	static uint8_t flash_disk_bounce_##n[CONFIG_FLASH_DISK_MAX_SECTOR_SIZE];	\
											\
	static struct flash_disk_data flash_disk_data_##n = {				\
		.bounce = flash_disk_bounce_##n,					\
	};										\
											\
	static const struct flash_disk_config flash_disk_config_##n = {			\
		.disk = DT_INST_PROP(n, disk_name),					\
		.offset = DT_INST_REG_ADDR(n),						\
		.size = DT_INST_REG_SIZE(n),						\
		.erase_block_size = DT_INST_PROP(n, erase_block_size),			\
		.write_block_size = DT_INST_PROP(n, write_block_size),			\
		.erase_value = DT_INST_PROP(n, erase_value),				\
		.layout = {								\
			.pages_size = DT_INST_PROP(n, erase_block_size),		\
			.pages_count = DT_INST_REG_SIZE(n) /				\
				       DT_INST_PROP(n, erase_block_size),		\
		},									\
		.params = {								\
			.write_block_size = DT_INST_PROP(n, write_block_size),	\
			.erase_value = DT_INST_PROP(n, erase_value),		\
		},									\
	};										\
											\
	DEVICE_DT_INST_DEFINE(n, flash_disk_init, NULL,					\
			      &flash_disk_data_##n, &flash_disk_config_##n,		\
			      POST_KERNEL, CONFIG_FLASH_DISK_INIT_PRIORITY,			\
			      &flash_disk_api);

DT_INST_FOREACH_STATUS_OKAY(FLASH_DISK_DEFINE)
