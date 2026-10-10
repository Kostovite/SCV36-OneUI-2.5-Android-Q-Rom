/* stand-in for the S8 Pie camera.msm8998.so: HMI in .bss filled by a constructor (like the real 0x64db8 init),
 * camera_device_open / open_legacy reject any module but &HMI (real 0x68fec / 0x68500), -38 otherwise.
 * Opened devices are HAL1 camera_device_t (version 0x100, 23 ops, close at +0x3c) that count their calls. */
extern int printf(const char *, ...);
extern void *memcpy(void *, const void *, unsigned);
typedef struct { int (*open)(const void *, const char *, void **); } methods_t;
__attribute__((visibility("default"))) unsigned char HMI[176];

/* call counters the test reads back through dlsym */
__attribute__((visibility("default"))) int fake_counts[8];   /* 0 start 1 stop 2 release 3 close 4 set_callbacks */

static int start_preview(void *d) { fake_counts[0]++; return 0; }
static void stop_preview(void *d) { fake_counts[1]++; }
static void release(void *d) { fake_counts[2]++; }
static int set_callbacks(void *d, void *n, void *a, void *b, void *c, void *u) { fake_counts[4]++; return 0; }
static int nop(void *d) { return 0; }
static int dev_close(void *d) { fake_counts[3]++; return 0; }
static void *ops[23];
static struct { unsigned tag, version; void *module; unsigned reserved[12]; int (*close)(void *); void **ops; void *priv; } dev;

static int dev_open(const void *m, const char *id, void **out)
{
	int i;
	if (m != (void *)HMI) { printf("FAKEHAL: Invalid module. Trying to open %p, expect %p\n", m, HMI); return -38; }
	for (i = 0; i < 23; i++) ops[i] = (void *)nop;
	ops[1] = (void *)set_callbacks; ops[5] = (void *)start_preview; ops[6] = (void *)stop_preview;
	ops[21] = (void *)release;
	dev.tag = 0x48574454; dev.version = 0x100; dev.module = HMI; dev.close = dev_close; dev.ops = ops;
	*out = &dev; printf("FAKEHAL: open %s ok\n", id); return 0;
}
static int open_legacy(const void *m, const char *id, unsigned v, void **out)
{
	if (m != (void *)HMI) { printf("FAKEHAL: legacy Invalid module\n"); return -38; }
	printf("FAKEHAL: open_legacy %s %#x ok\n", id, v);
	return dev_open(m, id, out);
}
static int nr(void) { return 2; }
static int torch(const char *id, int on) { printf("FAKEHAL: set_torch_mode %s %d\n", id, on); return 0; }
/* vendor tags like QCamera3VendorTags: two tags in sections 0x8000 and 0x8003 */
typedef struct vt { int (*count)(const struct vt *); void (*all)(const struct vt *, unsigned *);
	const char *(*sec)(const struct vt *, unsigned); const char *(*name)(const struct vt *, unsigned);
	int (*type)(const struct vt *, unsigned); void *r[8]; } vt_t;
static int vt_count(const vt_t *v) { return 2; }
static void vt_all(const vt_t *v, unsigned *t) { t[0] = 0x80000000; t[1] = 0x80030001; }
static const char *vt_sec(const vt_t *v, unsigned t) { return t == 0x80000000 ? "org.codeaurora.qcamera3.fake" : "samsung.android.control"; }
static const char *vt_name(const vt_t *v, unsigned t) { return t == 0x80000000 ? "fakeTag" : "aeMode"; }
static int vt_type(const vt_t *v, unsigned t) { return t == 0x80000000 ? 0 : 3; }
static void get_vendor_tag_ops(vt_t *o) { o->count = vt_count; o->all = vt_all; o->sec = vt_sec; o->name = vt_name; o->type = vt_type; }
static methods_t methods = { dev_open };
static const struct { unsigned tag; unsigned short mv, hv; const char *id, *name, *author; methods_t *m; void *dso; } tmpl =
	{ 0x48574d54, 0x204, 0x100, "camera", "QCamera Module", "Qualcomm", &methods, 0 };
__attribute__((constructor)) static void init(void)
{
	memcpy(HMI, &tmpl, sizeof(tmpl));
	*(void **)(HMI + 0x80) = (void *)nr;
	*(void **)(HMI + 0x8c) = (void *)get_vendor_tag_ops;
	*(void **)(HMI + 0x90) = (void *)open_legacy;
	*(void **)(HMI + 0x94) = (void *)torch;
}
