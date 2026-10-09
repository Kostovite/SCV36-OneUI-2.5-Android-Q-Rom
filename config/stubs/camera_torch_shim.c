/*
 * camera.msm8998.so - S8 port wrapper around the S8 Pie QCamera2 HAL module (renamed camera.msm8998_s8.so).
 *
 * One UI 2's torch level slider: SystemUI -> ICameraService.setTorchModeStrength -> CameraProviderManager
 * DeviceInfo1::setTorchMode(on, strength) -> vendor.samsung.camera.device@1.0 CameraDevice::secSetTorchModeStrength
 * -> CameraModule::sehSetTorchModeStrength -> camera_module_t slot +0xa8 "set_torch_mode_strength"
 * (const char *camera_id, bool enabled, int strength). The S8 Pie HAL leaves that slot NULL (reserved on Pie) ->
 * -ENOSYS -> cameraserver "Camera 0 has no flashlight" -> SystemUI crash (boot 22, reverse engineered from the G9600
 * libcameraservice / libcamerahardwareinterface and the T835 vendor.samsung.camera.device@1.0-impl).
 *
 * This module copies the real HAL_MODULE_INFO_SYM (open/open_legacy re-pointed at the real module, which they
 * check) and fills slot +0xa8: torch on through the real set_torch_mode
 * (+0x94, keeps the torch status callbacks), then the level through the S2MPB02 torch sysfs, which takes
 * 1001..1010 (drivers/leds/leds-s2mpb02.c: One UI "Flashlight level 1..5" = 1001, 1002, 1004, 1006, 1009).
 * Built by tools/build/build_stubs.sh (armv7, no sysroot: libc/libdl/liblog prototypes declared here).
 */
typedef unsigned int size_t;
typedef int bool_t;

extern void *dlopen(const char *file, int mode);
extern void *dlsym(void *handle, const char *name);
extern char *dlerror(void);
extern void *memcpy(void *d, const void *s, size_t n);
extern int strcmp(const char *a, const char *b);
extern int open(const char *path, int flags, ...);
extern long write(int fd, const void *buf, size_t n);
extern int close(int fd);
extern int __android_log_print(int prio, const char *tag, const char *fmt, ...);

#define RTLD_NOW 2
#define O_WRONLY 1
#define LOG_I 4
#define LOG_E 6
#define TAG "S8TorchShim"

#define REAL_HAL "/vendor/lib/hw/camera.msm8998_s8.so"
#define TORCH_SYSFS "/sys/class/camera/flash/rear_flash"
#define MODULE_SIZE 0xc0            /* >= S8 Pie HMI (176 bytes); slot +0xa8 is inside it */
#define OFF_METHODS 0x14            /* hw_module_t.methods (tag, 2x u16 versions, id, name, author, methods, dso) */
#define OFF_OPEN_LEGACY 0x90
#define OFF_SET_TORCH_MODE 0x94
#define OFF_SET_TORCH_STRENGTH 0xa8

typedef int (*set_torch_mode_fn)(const char *camera_id, bool_t enabled);
typedef int (*open_fn)(const void *module, const char *id, void **device);
typedef int (*open_legacy_fn)(const void *module, const char *id, unsigned int hal_version, void **device);

/* hw_get_module() dlsym()s "HMI" (HAL_MODULE_INFO_SYM_AS_STR) - filled from the real module at load time */
__attribute__((visibility("default"), aligned(8))) unsigned char HMI[MODULE_SIZE];

static set_torch_mode_fn real_set_torch_mode;
static const void *real_module;
static open_fn real_open;
static open_legacy_fn real_open_legacy;
static struct { open_fn open; } shim_methods;

/*
 * Samsung "preview started" event for the S8 SamsungCamera 9.0. The app activates its shooting mode (every button,
 * shutter, mode switch) only after SemCamera CommonEventListener.onPreviewStarted(), i.e. the notify message
 * COMMON_SHOT_PREVIEW_STARTED (0xf412) that it requests with sendCommand(1473) right before startPreview(). The S8
 * Pie QCamera2 HAL never sends it (the Pie Samsung cameraserver did); the app resolves SemCamera from the boot
 * framework.jar, so a semcamera.jar patch cannot reach it. The G9600 cameraserver passes any notify with
 * (msg & 0xfffff805) != 0 straight to the client ("lockIfMessageWanted : samsung defined callback msg", no lock, no
 * msg-enabled check, CameraClient::handleGenericNotify), so the HAL side sends it: after every successful
 * start_preview, a short-lived thread calls the device's notify callback with 0xf412. Apps on plain android.hardware
 * .Camera only log "Unknown message type". g_lock keeps the notify away from stop_preview / release / close.
 */
typedef void (*notify_cb_fn)(int msg_type, int ext1, int ext2, void *user);
typedef int (*set_callbacks_fn)(void *dev, notify_cb_fn notify, void *data, void *data_ts, void *get_memory, void *user);
typedef int (*dev_fn)(void *dev);
typedef void (*dev_void_fn)(void *dev);
typedef int (*close_fn)(void *dev);

extern int pthread_create(long *thread, const void *attr, void *(*fn)(void *), void *arg);
extern int pthread_detach(long thread);
extern int pthread_mutex_lock(void *m);
extern int pthread_mutex_unlock(void *m);
extern int usleep(unsigned int usec);

#define HAL1_VERSION 0x100            /* CAMERA_DEVICE_API_VERSION_1_0 */
#define DEV_OFF_VERSION 0x04          /* camera_device_t: hw_device_t common (64 bytes on LP32) */
#define DEV_OFF_CLOSE 0x3c
#define DEV_OFF_OPS 0x40
#define OPS_COUNT 23                  /* camera_device_ops_t (QCamera2HardwareInterface::mCameraOps st_size 92) */
#define OP_SET_CALLBACKS 1
#define OP_START_PREVIEW 5
#define OP_STOP_PREVIEW 6
#define OP_RELEASE 21
#define MSG_PREVIEW_STARTED 0xf412    /* SemCamera COMMON_SHOT_PREVIEW_STARTED */
#define PREVIEW_STARTED_DELAY_US 500000
#define MAX_DEVS 8

struct dev_wrap {
	void *dev;                    /* camera_device_t of the real HAL, NULL = free slot */
	void *ops[OPS_COUNT];         /* copy of its ops with our entries */
	void **real_ops;
	close_fn real_close;
	notify_cb_fn notify;
	void *user;
	unsigned int gen;             /* bumped by start/stop/release/close: a pending notify only fires if unchanged */
};

static struct dev_wrap g_devs[MAX_DEVS];   /* never freed: a sleeping notify thread may still look at a slot */
static int g_lock[4];                      /* bionic LP32 pthread_mutex_t, zero = PTHREAD_MUTEX_INITIALIZER */

static struct dev_wrap *find_wrap(void *dev)
{
	int i;
	for (i = 0; i < MAX_DEVS; i++)
		if (g_devs[i].dev == dev)
			return &g_devs[i];
	return 0;
}

static int w_set_callbacks(void *dev, notify_cb_fn notify, void *data, void *data_ts, void *get_memory, void *user)
{
	struct dev_wrap *w;
	pthread_mutex_lock(g_lock);
	w = find_wrap(dev);
	if (w) {
		w->notify = notify;
		w->user = user;
	}
	pthread_mutex_unlock(g_lock);
	if (!w)
		return -19;
	return ((set_callbacks_fn)w->real_ops[OP_SET_CALLBACKS])(dev, notify, data, data_ts, get_memory, user);
}

struct pending { struct dev_wrap *w; unsigned int gen; };
static struct pending g_pending[MAX_DEVS];

static void *preview_started_thread(void *arg)
{
	struct pending *p = arg;
	usleep(PREVIEW_STARTED_DELAY_US);
	pthread_mutex_lock(g_lock);
	if (p->w->dev && p->w->gen == p->gen && p->w->notify) {
		p->w->notify(MSG_PREVIEW_STARTED, 0, 0, p->w->user);
		__android_log_print(LOG_I, TAG, "preview started -> notify 0x%x", MSG_PREVIEW_STARTED);
	}
	pthread_mutex_unlock(g_lock);
	return 0;
}

static int w_start_preview(void *dev)
{
	struct dev_wrap *w;
	struct pending *p;
	long t;
	int ret;

	pthread_mutex_lock(g_lock);
	w = find_wrap(dev);
	if (w)
		w->gen++;
	pthread_mutex_unlock(g_lock);
	if (!w)
		return -19;
	ret = ((dev_fn)w->real_ops[OP_START_PREVIEW])(dev);
	if (ret)
		return ret;
	pthread_mutex_lock(g_lock);
	p = &g_pending[w - g_devs];
	p->w = w;
	p->gen = w->gen;
	pthread_mutex_unlock(g_lock);
	if (pthread_create(&t, 0, preview_started_thread, p) == 0)
		pthread_detach(t);
	else
		__android_log_print(LOG_E, TAG, "preview started thread failed");
	return ret;
}

static void w_stop_preview(void *dev)
{
	struct dev_wrap *w;
	pthread_mutex_lock(g_lock);
	w = find_wrap(dev);
	if (w)
		w->gen++;
	pthread_mutex_unlock(g_lock);
	if (w)
		((dev_void_fn)w->real_ops[OP_STOP_PREVIEW])(dev);
}

static void w_release(void *dev)
{
	struct dev_wrap *w;
	pthread_mutex_lock(g_lock);
	w = find_wrap(dev);
	if (w) {
		w->gen++;
		w->notify = 0;
	}
	pthread_mutex_unlock(g_lock);
	if (w)
		((dev_void_fn)w->real_ops[OP_RELEASE])(dev);
}

static int w_close(void *dev)
{
	struct dev_wrap *w;
	close_fn real_close = 0;
	pthread_mutex_lock(g_lock);
	w = find_wrap(dev);
	if (w) {
		real_close = w->real_close;
		w->gen++;
		w->notify = 0;
		w->dev = 0;
	}
	pthread_mutex_unlock(g_lock);
	return real_close ? real_close(dev) : -19;
}

/* after a successful open: give a HAL1 device our ops table (the HAL itself only uses device->priv) */
static void wrap_device(void *dev)
{
	struct dev_wrap *w = 0;
	int i;

	if (!dev || *(unsigned int *)((char *)dev + DEV_OFF_VERSION) != HAL1_VERSION)
		return;
	pthread_mutex_lock(g_lock);
	if (find_wrap(dev)) {             /* already ours (never re-wrap: real_ops would point at our own table) */
		pthread_mutex_unlock(g_lock);
		return;
	}
	for (i = 0; i < MAX_DEVS && !w; i++)
		if (!g_devs[i].dev)
			w = &g_devs[i];
	if (w) {
		w->real_ops = *(void ***)((char *)dev + DEV_OFF_OPS);
		w->real_close = *(close_fn *)((char *)dev + DEV_OFF_CLOSE);
		memcpy(w->ops, w->real_ops, sizeof(w->ops));
		w->ops[OP_SET_CALLBACKS] = (void *)w_set_callbacks;
		w->ops[OP_START_PREVIEW] = (void *)w_start_preview;
		w->ops[OP_STOP_PREVIEW] = (void *)w_stop_preview;
		w->ops[OP_RELEASE] = (void *)w_release;
		w->notify = 0;
		w->dev = dev;
		*(void ***)((char *)dev + DEV_OFF_OPS) = w->ops;
		*(close_fn *)((char *)dev + DEV_OFF_CLOSE) = w_close;
	}
	pthread_mutex_unlock(g_lock);
	if (!w)
		__android_log_print(LOG_E, TAG, "no free device slot, preview-started event disabled");
}

/* QCamera2Factory::camera_device_open / open_legacy reject any module but their own HAL_MODULE_INFO_SYM
 * ("Invalid module. Trying to open %p, expect %p" -> every app "camera in use"), so hand them theirs. */
static int shim_open(const void *module, const char *id, void **device)
{
	int ret;
	(void)module;
	ret = real_open(real_module, id, device);
	if (ret == 0)
		wrap_device(*device);
	return ret;
}

static int shim_open_legacy(const void *module, const char *id, unsigned int hal_version, void **device)
{
	int ret;
	(void)module;
	ret = real_open_legacy(real_module, id, hal_version, device);
	if (ret == 0)
		wrap_device(*device);
	return ret;
}

static int level_to_sysfs(int strength)
{
	static const int one_ui[] = { 1001, 1002, 1004, 1006, 1009 };   /* One UI levels 1..5 */
	if (strength >= 1001 && strength <= 1010)
		return strength;                                        /* already a kernel level */
	if (strength >= 1 && strength <= 5)
		return one_ui[strength - 1];
	if (strength >= 6 && strength <= 10)
		return 1000 + strength;
	return strength <= 0 ? 1001 : 1009;
}

static int set_torch_mode_strength(const char *camera_id, bool_t enabled, int strength)
{
	int ret, fd, v, n = 0;
	char buf[8], *p = buf + sizeof(buf);

	if (!real_set_torch_mode)
		return -38;
	if (!enabled || strcmp(camera_id, "0"))
		return real_set_torch_mode(camera_id, enabled);   /* off, or a camera without the S2MPB02 torch */
	ret = real_set_torch_mode(camera_id, 1);              /* on + torch status callback (default 60 mA) */
	if (ret)
		return ret;
	v = level_to_sysfs(strength);
	do { *--p = '0' + v % 10; v /= 10; n++; } while (v);
	fd = open(TORCH_SYSFS, O_WRONLY);
	if (fd < 0) {
		__android_log_print(LOG_E, TAG, "open %s failed, torch stays at the default level", TORCH_SYSFS);
		return 0;
	}
	if (write(fd, p, n) != n)
		__android_log_print(LOG_E, TAG, "write %s failed", TORCH_SYSFS);
	close(fd);
	__android_log_print(LOG_I, TAG, "camera %s torch on, strength %d -> %.*s", camera_id, strength, n, p);
	return 0;
}

#ifdef SHIM_DEBUG
/* qemu test harness only (tools: scratch shimtest): raw stderr dump, no logd there */
static void dbg(const char *tag, unsigned long a, unsigned long b, unsigned long c, unsigned long d)
{
	static const char hx[] = "0123456789abcdef";
	unsigned long v[4] = { a, b, c, d };
	char s[48], *q = s; int i, k;
	for (i = 0; i < 4; i++) { *q++ = 0x20; for (k = 28; k >= 0; k -= 4) *q++ = hx[(v[i] >> k) & 15]; }
	*q++ = 0x0a; write(2, "SHIM ", 5); write(2, tag, 4); write(2, s, q - s);
}
#define DBG(t, a, b, c, d) dbg(t, (unsigned long)(a), (unsigned long)(b), (unsigned long)(c), (unsigned long)(d))
#else
#define DBG(t, a, b, c, d) do { } while (0)
#endif

__attribute__((constructor)) static void shim_init(void)
{
	void *h = dlopen(REAL_HAL, RTLD_NOW);
	unsigned char *real;

	if (!h || !(real = dlsym(h, "HMI"))) {
		__android_log_print(LOG_E, TAG, "cannot load %s: %s", REAL_HAL, dlerror());
		return;
	}
	DBG("pre ", h, real, HMI, *(unsigned long *)(real + OFF_METHODS));
	memcpy(HMI, real, 0xb0);     /* S8 Pie HMI st_size = 176 (.bss, filled by the HAL's own constructor) */
	DBG("post", h, real, HMI, *(unsigned long *)(real + OFF_METHODS));
	real_module = real;
	real_open = **(open_fn **)(real + OFF_METHODS);
	shim_methods.open = shim_open;
	*(void **)(HMI + OFF_METHODS) = &shim_methods;
	real_open_legacy = *(open_legacy_fn *)(real + OFF_OPEN_LEGACY);
	if (real_open_legacy)
		*(void **)(HMI + OFF_OPEN_LEGACY) = (void *)shim_open_legacy;
	real_set_torch_mode = *(set_torch_mode_fn *)(real + OFF_SET_TORCH_MODE);
	if (!*(void **)(HMI + OFF_SET_TORCH_STRENGTH))
		*(void **)(HMI + OFF_SET_TORCH_STRENGTH) = (void *)set_torch_mode_strength;
	__android_log_print(LOG_I, TAG, "wrapped %s (set_torch_mode %p, strength slot filled)", REAL_HAL,
			    (void *)real_set_torch_mode);
}
