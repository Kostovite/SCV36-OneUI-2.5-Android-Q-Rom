/* hw_get_module() + CameraModule + sehSetTorchModeStrength as the provider does it */
extern int printf(const char *, ...);
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *dlerror(void);
extern int strcmp(const char *, const char *);
extern void exit(int);
extern void __libc_init(void *raw_args, void (*onexit)(void), int (*main)(int, char **, char **), void *structors);
extern int usleep(unsigned int);
typedef struct { int (*open)(const void *, const char *, void **); } methods_t;
static volatile int g_notifies, g_last_msg;
static void *volatile g_last_user;
static void notify_rec(int msg, int e1, int e2, void *user) { g_notifies++; g_last_msg = msg; g_last_user = user; }
int main(int argc, char **argv, char **envp)
{
	void *h = dlopen("/vendor/lib/hw/camera.msm8998.so", 2), *dev = 0;
	unsigned char *hmi;
	int r, fails = 0;
	if (!h) { printf("dlopen: %s\n", dlerror()); return 1; }
	hmi = dlsym(h, "HMI");
	if (!hmi) { printf("dlsym: %s\n", dlerror()); return 1; }
	printf("id=%s name=%s api=%#x\n", *(char **)(hmi + 8), *(char **)(hmi + 12), *(unsigned short *)(hmi + 4));
	if (strcmp(*(char **)(hmi + 8), "camera")) fails++;
	*(void **)(hmi + 0x18) = h;                                   /* hmi->dso = handle */
	if (argc > 1) {	/* real HAL: module check only (it runs before any hardware access) */
		void *rh = dlopen("/vendor/lib/hw/camera.msm8998_s8.so", 2);
		unsigned char *rm = dlsym(rh, "HMI");
		methods_t *rmeth = *(methods_t **)(rm + 0x14);
		r = rmeth->open(hmi, "0", &dev);
		printf("control: real open with the wrapper module -> %d (expect -38)\n", r);
		r = (*(int (**)(const void *, const char *, unsigned, void **))(rm + 0x90))(hmi, "0", 0x100, &dev);
		printf("control: real open_legacy with the wrapper module -> %d (expect -38)\n", r);
		r = (*(methods_t **)(hmi + 0x14))->open(hmi, "0", &dev);
		printf("wrapper open -> %d (anything but -38 = module check passed)\n", r);
		r = (*(int (**)(const void *, const char *, unsigned, void **))(hmi + 0x90))(hmi, "0", 0x100, &dev);
		printf("wrapper open_legacy -> %d (anything but -38 = module check passed)\n", r);
		return 0;
	}
	printf("cameras=%d\n", (*(int (**)(void))(hmi + 0x80))());
	r = (*(methods_t **)(hmi + 0x14))->open(hmi, "0", &dev); printf("open -> %d dev=%p\n", r, dev); fails += r != 0;
	{	/* HAL1 device wrapper: preview-started notify (0xf412) after start_preview, never after stop/release/close */
		void **ops = *(void ***)((char *)dev + 0x40);
		int *cnt = dlsym(h, "fake_counts");
		if (!cnt) { void *fh = dlopen("/vendor/lib/hw/camera.msm8998_s8.so", 2); cnt = dlsym(fh, "fake_counts"); }
		((int (*)(void *, void *, void *, void *, void *, void *))ops[1])(dev, (void *)notify_rec, 0, 0, 0, (void *)0xc00c1e);
		((int (*)(void *))ops[5])(dev);
		usleep(800000);
		printf("start_preview -> notifies=%d msg=%#x user=%p\n", g_notifies, g_last_msg, g_last_user);
		fails += !(g_notifies == 1 && g_last_msg == 0xf412 && g_last_user == (void *)0xc00c1e);
		((int (*)(void *))ops[5])(dev); ((void (*)(void *))ops[6])(dev);
		usleep(800000);
		printf("start+immediate stop -> notifies=%d (expect 1)\n", g_notifies); fails += g_notifies != 1;
		((int (*)(void *))ops[5])(dev); ((void (*)(void *))ops[21])(dev);
		r = (*(int (**)(void *))((char *)dev + 0x3c))(dev);
		usleep(800000);
		printf("start+release+close -> close=%d notifies=%d (expect 1)\n", r, g_notifies); fails += g_notifies != 1 || r;
		printf("real HAL saw: start=%d stop=%d release=%d close=%d set_callbacks=%d (expect 3 1 1 1 1)\n",
		       cnt[0], cnt[1], cnt[2], cnt[3], cnt[4]);
		fails += !(cnt[0] == 3 && cnt[1] == 1 && cnt[2] == 1 && cnt[3] == 1 && cnt[4] == 1);
	}
	r = (*(int (**)(const void *, const char *, unsigned, void **))(hmi + 0x90))(hmi, "1", 0x100, &dev);
	printf("open_legacy -> %d dev=%p\n", r, dev); fails += r != 0;
	{	/* vendor tags: the HAL's 2 kept, samsung.android.control.shootingMode/pafMode (int32) added in a new section */
		struct vt { int (*count)(const void *); void (*all)(const void *, unsigned *);
			const char *(*sec)(const void *, unsigned); const char *(*name)(const void *, unsigned);
			int (*type)(const void *, unsigned); void *rsv[8]; } o;
		unsigned tags[8] = { 0 };
		int n, i, found = 0;
		(*(void (**)(struct vt *))(hmi + 0x8c))(&o);
		n = o.count(&o); o.all(&o, tags);
		for (i = 0; i < n && i < 8; i++)
			printf("  tag %#x %s.%s type %d\n", tags[i], o.sec(&o, tags[i]), o.name(&o, tags[i]), o.type(&o, tags[i]));
		for (i = 0; i < n && i < 8; i++)
			if (!strcmp(o.sec(&o, tags[i]), "samsung.android.control") && o.type(&o, tags[i]) == 1 &&
			    (!strcmp(o.name(&o, tags[i]), "shootingMode") || !strcmp(o.name(&o, tags[i]), "pafMode")) &&
			    (tags[i] >> 16) > 0x8003)
				found++;
		printf("vendor tags: count=%d added=%d (expect 4, 2)\n", n, found);
		fails += !(n == 4 && found == 2 && tags[0] == 0x80000000 && tags[1] == 0x80030001 &&
			   !strcmp(o.name(&o, 0x80030001), "aeMode") && o.type(&o, 0x80000000) == 0);
	}
	r = (*(int (**)(const char *, int))(hmi + 0x94))("0", 1); printf("set_torch_mode -> %d\n", r); fails += r != 0;
	r = (*(int (**)(const char *, int, int))(hmi + 0xa8))("0", 1, 3); printf("strength(0,on,3) -> %d\n", r); fails += r != 0;
	r = (*(int (**)(const char *, int, int))(hmi + 0xa8))("0", 0, 3); printf("strength(0,off) -> %d\n", r); fails += r != 0;
	printf(fails ? "FAIL %d\n" : "PASS\n", fails);
	return fails;
}
static struct { void *a, *b, *c; } structors;
__attribute__((used)) void _start_c(void *raw) { __libc_init(raw, 0, main, &structors); }
__attribute__((naked, used)) void _start(void) { __asm__("mov r0, sp; b _start_c"); }
