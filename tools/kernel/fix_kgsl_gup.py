"""Runs ON the build server (python3): adapt the transplanted Pie kgsl.c to the 4.4.205 get_user_pages() signature
(write/force ints -> gup_flags, as the Q tree's own kgsl does). Idempotent."""
import os
p = os.path.expanduser('~/s8rom/kernel/t830_q/drivers/gpu/msm/kgsl.c')
s = open(p).read()
old = '''get_user_pages(current, current->mm, memdesc->useraddr,
					sglen, write, 0, pages, NULL);'''
new = '''get_user_pages(current, current->mm, memdesc->useraddr,
					sglen, write ? FOLL_WRITE : 0, pages, NULL);'''
if new in s:
    print('already fixed')
else:
    assert s.count(old) == 1, 'call site not found'
    open(p, 'w').write(s.replace(old, new))
    print('fixed get_user_pages call in', p)
