/*
 * libsdtv_compat.so (arm64) - Pie -> Q ABI bridge for the SCV36 ISDB-T TV middleware (S8 Pie libSDtvPorting /
 * libonesegutils loaded by /system/bin/SDtvService and the MobileTV app JNI). Added as NEEDED to those two libs by
 * tools/build/make_vendor_push.sh. Only three imports of the whole TV stack are missing on the G9600 Q system:
 *   android::GraphicBuffer::lock(uint32_t usage, void **vaddr)   Q: lock(usage, vaddr, int32_t *outBytesPerPixel,
 *                                                                    int32_t *outBytesPerStride) (both nullable)
 *   get_malloc_leak_info() / free_malloc_leak_info()              removed from bionic in Q (debug-only caller)
 * Built by tools/build/build_stubs.sh (no sysroot; link stand-in for libui exports the Q symbol name).
 */
typedef unsigned long size_t;

extern int _ZN7android13GraphicBuffer4lockEjPPvPiS3_(void *self, unsigned int usage, void **vaddr,
						     int *out_bytes_per_pixel, int *out_bytes_per_stride);

__attribute__((visibility("default")))
int _ZN7android13GraphicBuffer4lockEjPPv(void *self, unsigned int usage, void **vaddr)
{
	return _ZN7android13GraphicBuffer4lockEjPPvPiS3_(self, usage, vaddr, 0, 0);
}

__attribute__((visibility("default")))
void get_malloc_leak_info(unsigned char **info, size_t *overall_size, size_t *info_size, size_t *total_memory,
			  size_t *backtrace_size)
{
	*info = 0;
	*overall_size = 0;
	*info_size = 0;
	*total_memory = 0;
	*backtrace_size = 0;
}

/* free_malloc_leak_info(): the matching free for the above, also gone from Q bionic (found by the full TV-stack
 * symbol audit against Q libc/libm/libdl, 2026-10-09: the only other missing import, in libonesegutils) */
__attribute__((visibility("default")))
void free_malloc_leak_info(unsigned char *info)
{
	(void)info;
}
