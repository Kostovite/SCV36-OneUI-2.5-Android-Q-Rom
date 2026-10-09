"""Runs ON the build server (python3): extend the 's8dbg.recovery' debug hook in msm-poweroff.c with a reboot notifier
that writes the kernel log to the start of the 'cache' partition (raw, header 'S8DBGLOG') before the restart.
Needed because this phone always hard-resets (RAM/pstore is wiped). Idempotent. Requires patch_s8dbg.py first."""
import os, sys
p = os.path.expanduser('~/s8rom/kernel/t830_q/drivers/power/reset/msm-poweroff.c')
s = open(p).read()
assert 's8dbg_recovery' in s, 'run patch_s8dbg.py first'
if 's8dbg_logdump' in s:
    print('already patched'); sys.exit(0)

includes = '''#include <linux/kmsg_dump.h>
#include <linux/blkdev.h>
#include <linux/genhd.h>
#include <linux/bio.h>
#include <linux/gfp.h>
'''
first_inc = s.index('#include')
s = s[:first_inc] + includes + s[first_inc:]

code = '''__setup("s8dbg.recovery", s8dbg_recovery_setup);

/*
 * s8dbg log dump: in debug mode, copy the printk buffer to the start of the 'cache' partition on reboot
 * (process context, storage still up). Layout: 4 KiB header "S8DBGLOG <len> <reboot cmd>", then the log.
 */
#define S8DBG_LOG_MAX	(2 << 20)
static struct block_device *s8dbg_find_part(const char *name)
{
	struct class_dev_iter iter;
	struct device *dev;
	dev_t devt = 0;

	class_dev_iter_init(&iter, &block_class, NULL, &part_type);
	while ((dev = class_dev_iter_next(&iter))) {
		struct hd_struct *part = dev_to_part(dev);

		if (part->info && !strcmp((char *)part->info->volname, name)) {
			devt = dev->devt;
			break;
		}
	}
	class_dev_iter_exit(&iter);
	if (!devt)
		return NULL;
	return blkdev_get_by_dev(devt, FMODE_WRITE, NULL);
}

static int s8dbg_logdump(struct notifier_block *nb, unsigned long code, void *data)
{
	struct kmsg_dumper dumper = { .active = true };
	struct block_device *bdev;
	unsigned int order = get_order(S8DBG_LOG_MAX + PAGE_SIZE);
	unsigned long buf;
	size_t len = 0, done;
	sector_t sector = 0;

	pr_emerg("s8dbg: reboot code=%lu cmd=%s - dumping kernel log to cache\\n",
		 code, data ? (char *)data : "");
	buf = __get_free_pages(GFP_KERNEL | __GFP_ZERO, order);
	if (!buf)
		return NOTIFY_DONE;
	kmsg_dump_rewind(&dumper);
	kmsg_dump_get_buffer(&dumper, false, (char *)buf + PAGE_SIZE, S8DBG_LOG_MAX, &len);
	snprintf((char *)buf, PAGE_SIZE, "S8DBGLOG %zu %s\\n", len, data ? (char *)data : "");

	bdev = s8dbg_find_part("cache");
	if (IS_ERR_OR_NULL(bdev)) {
		pr_emerg("s8dbg: cache partition not found\\n");
		goto out;
	}
	for (done = 0; done < PAGE_SIZE + len; ) {
		struct bio *bio = bio_alloc(GFP_KERNEL, BIO_MAX_PAGES);
		unsigned int n = 0;

		bio->bi_bdev = bdev;
		bio->bi_iter.bi_sector = sector;
		while (n < BIO_MAX_PAGES && done < PAGE_SIZE + len) {
			if (!bio_add_page(bio, virt_to_page(buf + done), PAGE_SIZE, 0))
				break;
			done += PAGE_SIZE;
			n++;
		}
		sector += (n * PAGE_SIZE) >> 9;
		submit_bio_wait(WRITE_SYNC, bio);
		bio_put(bio);
	}
	blkdev_put(bdev, FMODE_WRITE);
	pr_emerg("s8dbg: wrote %zu bytes of kernel log to cache\\n", len);
out:
	free_pages(buf, order);
	return NOTIFY_DONE;
}

static struct notifier_block s8dbg_reboot_nb = {
	.notifier_call = s8dbg_logdump,
	.priority = INT_MIN,	/* last notifier: capture as much shutdown output as possible */
};

static int __init s8dbg_logdump_init(void)
{
	if (s8dbg_recovery)
		register_reboot_notifier(&s8dbg_reboot_nb);
	return 0;
}
late_initcall(s8dbg_logdump_init);
'''
anchor = '__setup("s8dbg.recovery", s8dbg_recovery_setup);\n'
assert s.count(anchor) == 1
s = s.replace(anchor, code, 1)
open(p, 'w').write(s)
print('patched', p)
