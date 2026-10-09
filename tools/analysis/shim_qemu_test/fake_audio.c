/* stand-in for the S8 Pie audio.primary.msm8998.so: plain hw_module_t HMI, adev_open returns one static
 * audio_hw_device (ops at the AOSP LP32 offsets), exported adev_open/close_output_stream like the Pie HAL */
extern int printf(const char *, ...);
struct stream { void *ops[16]; int handle; };
static struct stream outs[4], ins[4];
static int nout, nin;
static int set_params(void *s, const char *kv) { printf("FAKEAUDIO: set_parameters(%p, %s)\n", s, kv); return 0; }
__attribute__((visibility("default"))) int adev_open_output_stream(void *dev, int handle, unsigned d, unsigned f,
		void *cfg, void **out, const char *a)
{ struct stream *s = &outs[nout++ & 3]; s->ops[10] = (void *)set_params; s->handle = handle; *out = s; return 0; }
__attribute__((visibility("default"))) void adev_close_output_stream(void *dev, void *s) { printf("FAKEAUDIO: close out %p\n", s); }
static int open_in(void *dev, int handle, unsigned d, void *cfg, void **in, unsigned f, const char *a, int src)
{ struct stream *s = &ins[nin++ & 3]; s->ops[10] = (void *)set_params; s->handle = handle; *in = s; return 0; }
static void close_in(void *dev, void *s) { printf("FAKEAUDIO: close in %p\n", s); }
static void *adev[40];
static int dev_open(const void *m, const char *id, void **out)
{
	adev[1] = (void *)0x300;                  /* version */
	adev[0x60 / 4] = (void *)set_params;      /* set_parameters */
	adev[0x6c / 4] = (void *)adev_open_output_stream;
	adev[0x70 / 4] = (void *)adev_close_output_stream;
	adev[0x74 / 4] = (void *)open_in;
	adev[0x78 / 4] = (void *)close_in;
	*out = adev; printf("FAKEAUDIO: adev_open(%s)\n", id); return 0;
}
static struct { int (*open)(const void *, const char *, void **); } methods = { dev_open };
__attribute__((visibility("default"))) struct { unsigned tag; unsigned short mv, hv; const char *id, *name, *author;
	void *methods, *dso; unsigned r[25]; } HMI = { 0x48574d54, 0x200, 0x100, "audio", "QCOM Audio HAL", "Qualcomm", &methods, 0 };
