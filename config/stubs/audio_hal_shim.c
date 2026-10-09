/*
 * audio.primary.msm8998.so - S8 port wrapper around the S8 Pie audio HAL (renamed audio.primary.msm8998_s8.so).
 *
 * Why the S8 Pie HAL: the speaker is a Maxim MAX98506 driven by Samsung's DSM speaker protection in the S8 HAL
 * (sec_dsm_spkr_prot_processing / sec_dsm_spkr_prot_control_tx_topology, VI feedback on TERT_MI2S_TX, S8
 * Speaker_cal.acdb). The Tab S4 (T835) Q HAL has the NXP TFA / Qualcomm WSA paths instead -> weak, thin speaker.
 *
 * What the wrapper adds: the One UI 2 Samsung audio extension (vendor.samsung.hardware.audio@1.0-impl ->
 * audio.sec_primary.default.so, used by the G9600 libaudiohal SecDevicesFactoryHal) loads the primary module and
 * dlsym()s two Q-only entry points the Pie HAL lacks (reverse engineered from the T835 HAL + audio.sec_primary):
 *   void *sec_get_audio_device_instance(void)                    -> the opened audio_hw_device
 *   void *sec_get_audio_stream_instance(void *adev, int handle, int type)  type 0 = output, 1 = input
 *     (sec_dev_open_audio_stream logs "handle 13, type 0" for outputs, "handle 14, type 1" for the input; the
 *      first build had them swapped -> every lookup failed and the policy dropped all inputs: no microphone)
 * and then only calls standard ops on them (adev +0x60/+0x64 set/get_parameters, stream +0x28/+0x2c). The wrapper
 * records the device on open and every stream by its io handle (open/close_output_stream +0x6c/+0x70,
 * open/close_input_stream +0x74/+0x78; the output slots are verified against the HAL's exported
 * adev_open_output_stream / adev_close_output_stream before anything is hooked).
 * Built by tools/build/build_stubs.sh (armv7, no sysroot: libc/libdl/liblog prototypes declared here).
 */
typedef unsigned int size_t;

extern void *dlopen(const char *file, int mode);
extern void *dlsym(void *handle, const char *name);
extern char *dlerror(void);
extern void *memcpy(void *d, const void *s, size_t n);
extern int pthread_mutex_lock(void *m);
extern int pthread_mutex_unlock(void *m);
extern int __android_log_print(int prio, const char *tag, const char *fmt, ...);

#define RTLD_NOW 2
#define LOG_I 4
#define LOG_E 6
#define TAG "S8AudioShim"

#define REAL_HAL "/vendor/lib/hw/audio.primary.msm8998_s8.so"
#define MODULE_SIZE 128             /* hw_module_t (S8 Pie HMI st_size 128) */
#define OFF_METHODS 0x14            /* hw_module_t.methods */
#define DEV_OPEN_OUTPUT 0x6c        /* audio_hw_device_t (hw_device_t common = 0x40 on LP32) */
#define DEV_CLOSE_OUTPUT 0x70
#define DEV_OPEN_INPUT 0x74
#define DEV_CLOSE_INPUT 0x78
#define MAX_STREAMS 64

typedef int (*open_fn)(const void *module, const char *id, void **device);
typedef int (*open_out_fn)(void *dev, int handle, unsigned devices, unsigned flags, void *config, void **out,
			   const char *address);
typedef void (*close_fn)(void *dev, void *stream);
typedef int (*open_in_fn)(void *dev, int handle, unsigned devices, void *config, void **in, unsigned flags,
			  const char *address, int source);

/* hw_get_module() dlsym()s "HMI" - filled from the real module at load time */
__attribute__((visibility("default"), aligned(8))) unsigned char HMI[MODULE_SIZE];

static void *real_module, *real_handle;
static open_fn real_open;
static struct { open_fn open; } shim_methods;
static open_out_fn real_open_out;
static close_fn real_close_out, real_close_in;
static open_in_fn real_open_in;
static void *g_adev;
static int g_lock[4];               /* bionic LP32 pthread_mutex_t, zero = PTHREAD_MUTEX_INITIALIZER */
static struct { int handle, type; void *stream; } g_streams[MAX_STREAMS];

static void remember(int handle, int type, void *stream)
{
	int i, free_slot = -1;
	pthread_mutex_lock(g_lock);
	for (i = 0; i < MAX_STREAMS; i++) {
		if (g_streams[i].stream && g_streams[i].handle == handle && g_streams[i].type == type)
			free_slot = i;          /* reopened handle: replace */
		else if (!g_streams[i].stream && free_slot < 0)
			free_slot = i;
	}
	if (free_slot >= 0) {
		g_streams[free_slot].handle = handle;
		g_streams[free_slot].type = type;
		g_streams[free_slot].stream = stream;
	}
	pthread_mutex_unlock(g_lock);
	if (free_slot < 0)
		__android_log_print(LOG_E, TAG, "stream table full, handle %d not tracked", handle);
}

static void forget(void *stream)
{
	int i;
	pthread_mutex_lock(g_lock);
	for (i = 0; i < MAX_STREAMS; i++)
		if (g_streams[i].stream == stream)
			g_streams[i].stream = 0;
	pthread_mutex_unlock(g_lock);
}

static int w_open_out(void *dev, int handle, unsigned devices, unsigned flags, void *config, void **out,
		      const char *address)
{
	int ret = real_open_out(dev, handle, devices, flags, config, out, address);
	if (ret == 0 && out && *out)
		remember(handle, 1, *out);
	return ret;
}

static void w_close_out(void *dev, void *stream)
{
	forget(stream);
	real_close_out(dev, stream);
}

static int w_open_in(void *dev, int handle, unsigned devices, void *config, void **in, unsigned flags,
		     const char *address, int source)
{
	int ret = real_open_in(dev, handle, devices, config, in, flags, address, source);
	if (ret == 0 && in && *in)
		remember(handle, 0, *in);
	return ret;
}

static void w_close_in(void *dev, void *stream)
{
	forget(stream);
	real_close_in(dev, stream);
}

static void hook_device(void *dev)
{
	char *d = dev;
	void *open_out = dlsym(real_handle, "adev_open_output_stream");
	void *close_out = dlsym(real_handle, "adev_close_output_stream");

	if (*(void **)(d + DEV_OPEN_OUTPUT) == (void *)w_open_out)
		return;                                  /* the Pie HAL returns the same adev on every open */
	if (!open_out || *(void **)(d + DEV_OPEN_OUTPUT) != open_out ||
	    !close_out || *(void **)(d + DEV_CLOSE_OUTPUT) != close_out) {
		__android_log_print(LOG_E, TAG, "unexpected audio_hw_device layout, stream lookup disabled");
		return;
	}
	real_open_out = open_out;
	real_close_out = close_out;
	real_open_in = *(open_in_fn *)(d + DEV_OPEN_INPUT);
	real_close_in = *(close_fn *)(d + DEV_CLOSE_INPUT);
	*(void **)(d + DEV_OPEN_OUTPUT) = (void *)w_open_out;
	*(void **)(d + DEV_CLOSE_OUTPUT) = (void *)w_close_out;
	*(void **)(d + DEV_OPEN_INPUT) = (void *)w_open_in;
	*(void **)(d + DEV_CLOSE_INPUT) = (void *)w_close_in;
}

static int shim_open(const void *module, const char *id, void **device)
{
	int ret;
	(void)module;
	ret = real_open(real_module, id, device);
	if (ret == 0 && device && *device) {
		pthread_mutex_lock(g_lock);
		hook_device(*device);
		g_adev = *device;
		pthread_mutex_unlock(g_lock);
	}
	return ret;
}

/* Q Samsung audio extension entry points (audio.sec_primary.default.so) */
__attribute__((visibility("default"))) void *sec_get_audio_device_instance(void)
{
	return g_adev;
}

__attribute__((visibility("default"))) void *sec_get_audio_stream_instance(void *adev, int handle, int type)
{
	void *s = 0;
	int i, want = type == 0 ? 1 : 0;           /* table: 1 = output, 0 = input */
	(void)adev;
	pthread_mutex_lock(g_lock);
	for (i = 0; i < MAX_STREAMS && !s; i++)
		if (g_streams[i].stream && g_streams[i].handle == handle && g_streams[i].type == want)
			s = g_streams[i].stream;
	pthread_mutex_unlock(g_lock);
	return s;
}

static int fail_open(const void *module, const char *id, void **device)
{
	(void)module;
	(void)id;
	if (device)
		*device = 0;
	return -19;                                     /* -ENODEV */
}

__attribute__((constructor)) static void shim_init(void)
{
	unsigned char *real;

	real_handle = dlopen(REAL_HAL, RTLD_NOW);
	if (!real_handle || !(real = dlsym(real_handle, "HMI"))) {
		__android_log_print(LOG_E, TAG, "cannot load %s: %s", REAL_HAL, dlerror());
		/* still a valid hw_module_t whose open fails: an all-zero HMI made libhardware strcmp(NULL id) ->
		 * SIGSEGV in the audio HAL service on every restart (0021: audio@2.0-service crash loop, UI freeze) */
		*(unsigned *)(HMI + 0x00) = 0x48574d54;          /* HARDWARE_MODULE_TAG */
		*(unsigned short *)(HMI + 0x04) = 0x0001;         /* AUDIO_MODULE_API_VERSION_0_1 */
		*(const char **)(HMI + 0x08) = "audio";           /* AUDIO_HARDWARE_MODULE_ID */
		*(const char **)(HMI + 0x0c) = "S8 audio wrapper (real HAL not loaded)";
		*(const char **)(HMI + 0x10) = "s8port";
		shim_methods.open = fail_open;
		*(void **)(HMI + OFF_METHODS) = &shim_methods;
		return;
	}
	memcpy(HMI, real, MODULE_SIZE);
	real_module = real;
	real_open = **(open_fn **)(real + OFF_METHODS);
	shim_methods.open = shim_open;
	*(void **)(HMI + OFF_METHODS) = &shim_methods;
	__android_log_print(LOG_I, TAG, "wrapped %s", REAL_HAL);
}
