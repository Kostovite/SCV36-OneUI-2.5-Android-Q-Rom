// Vendor stand-in for the S8 Pie /system/lib/libsensorlistener.so used by the S8 camera HAL (camera.msm8998.so,
// QCamera2HardwareInterface::SensorListenerThread: gyro / accelerometer / rotation / HRM / light-IR hints).
// The Pie library reads sensors through libandroid.so (ASensorManager/ALooper), which a vendor process may not load
// on Android 10 (not LLNDK/VNDK). This stub keeps the same exported C++ symbols: a valid dummy handle, enable fails,
// no data - the HAL runs without sensor hints instead of failing to dlopen.
// Build: tools/build_stubs.sh (clang, armv7, no libc dependency).

namespace android {
struct SensorListenerEvent;

static int g_dummy_handle;

void *sensor_listener_load() { return &g_dummy_handle; }

int sensor_listener_unload(void **handle) {
    if (handle) *handle = 0;
    return 0;
}

int sensor_listener_enable_sensor(void *, int, int) { return -1; }

int sensor_listener_disable_sensor(void *, int) { return 0; }

int sensor_listener_get_data(void *, int, SensorListenerEvent *, bool) { return 0; }
}  // namespace android
