/* what the T835 audio@5.0 impl + Samsung audio.sec_primary do with the wrapper */
extern int printf(const char *, ...);
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *dlerror(void);
extern int strcmp(const char *, const char *);
extern void __libc_init(void *raw_args, void (*onexit)(void), int (*main)(int, char **, char **), void *structors);
typedef struct { int (*open)(const void *, const char *, void **); } methods_t;
typedef int (*setp_fn)(void *, const char *);
int main(int argc, char **argv, char **envp)
{
	void *h = dlopen("/vendor/lib/hw/audio.primary.msm8998.so", 2), *dev = 0, *dev2 = 0, *o1, *o2, *i1;
	unsigned char *hmi; int fails = 0;
	void *(*get_dev)(void); void *(*get_stream)(void *, int, int);
	if (!h) { printf("dlopen: %s\n", dlerror()); return 1; }
	hmi = dlsym(h, "HMI"); get_dev = dlsym(h, "sec_get_audio_device_instance"); get_stream = dlsym(h, "sec_get_audio_stream_instance");
	printf("id=%s name=%s get_dev=%p get_stream=%p\n", *(char **)(hmi + 8), *(char **)(hmi + 12), get_dev, get_stream);
	if (!get_dev || !get_stream || strcmp(*(char **)(hmi + 8), "audio")) return 1;
	printf("device before open: %p (expect nil)\n", get_dev()); fails += get_dev() != 0;
	(*(methods_t **)(hmi + 0x14))->open(hmi, "audio_hw_if", &dev);
	(*(methods_t **)(hmi + 0x14))->open(hmi, "audio_hw_if", &dev2);      /* Pie HAL: same adev again */
	printf("device after open: %p (dev %p)\n", get_dev(), dev); fails += get_dev() != dev || dev2 != dev;
	((int (*)(void *, int, unsigned, unsigned, void *, void **, const char *))(*(void **)((char *)dev + 0x6c)))(dev, 13, 2, 0, 0, &o1, "");
	((int (*)(void *, int, unsigned, unsigned, void *, void **, const char *))(*(void **)((char *)dev + 0x6c)))(dev, 21, 2, 0, 0, &o2, "");
	((int (*)(void *, int, unsigned, void *, void **, unsigned, const char *, int))(*(void **)((char *)dev + 0x74)))(dev, 13, 4, 0, &i1, 0, "", 1);
	printf("out 13 -> %p (%p) out 21 -> %p (%p) in 13 -> %p (%p)\n", get_stream(dev, 13, 0), o1, get_stream(dev, 21, 0), o2, get_stream(dev, 13, 1), i1);
	fails += get_stream(dev, 13, 0) != o1 || get_stream(dev, 21, 0) != o2 || get_stream(dev, 13, 1) != i1 || get_stream(dev, 99, 0) != 0;
	/* audio.sec_primary: adev +0x60 set_parameters, stream +0x28 set_parameters */
	((setp_fn)(*(void **)((char *)get_dev() + 0x60)))(get_dev(), "l_sec_test=1");
	((setp_fn)(*(void **)((char *)get_stream(dev, 21, 0) + 0x28)))(get_stream(dev, 21, 0), "l_stream_test=1");
	((void (*)(void *, void *))(*(void **)((char *)dev + 0x70)))(dev, o1);
	((void (*)(void *, void *))(*(void **)((char *)dev + 0x78)))(dev, i1);
	printf("after close: out 13 -> %p in 13 -> %p out 21 -> %p\n", get_stream(dev, 13, 0), get_stream(dev, 13, 1), get_stream(dev, 21, 0));
	fails += get_stream(dev, 13, 0) != 0 || get_stream(dev, 13, 1) != 0 || get_stream(dev, 21, 0) != o2;
	printf(fails ? "FAIL %d\n" : "PASS\n", fails);
	return fails;
}
static struct { void *a, *b, *c; } structors;
__attribute__((used)) void _start_c(void *raw) { __libc_init(raw, 0, main, &structors); }
__attribute__((naked, used)) void _start(void) { __asm__("mov r0, sp; b _start_c"); }
