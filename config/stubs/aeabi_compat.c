/*
 * libaeabi_compat.so (armv7) - ARM EABI division-by-zero hooks for S8 Pie camera libs on the Q vendor.
 * The Pie bionic libc exported __aeabi_idiv0/__aeabi_ldiv0 (from its static libgcc); the Q libc does not, so
 * libOpenCv.camera.samsung.so / libxcv.camera.samsung.so failed to load -> no blur-detection camera plugin
 * (tools/build/vendor_symbol_audit.py). Added as NEEDED by tools/build/build_vendor.sh. Same behaviour as libgcc's default
 * hooks: return 0 (the quotient the caller then uses).
 */
__attribute__((visibility("default"))) int __aeabi_idiv0(int r)
{
	(void)r;
	return 0;
}

__attribute__((visibility("default"))) long long __aeabi_ldiv0(long long r)
{
	(void)r;
	return 0;
}
