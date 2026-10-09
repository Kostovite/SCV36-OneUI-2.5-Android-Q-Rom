"""Runs ON the build server (python3): make the Q-tree APR driver work with the S8 Pie device tree.
Q moved all APR init into apr_probe() (needs a "qcom,msm-audio-apr" DT node the S8 Pie DT doesn't have) -> the
delayed work was never initialised -> kernel BUG in adsp_load_fw. Fix: if no such node exists, run the same init at
device_initcall time (Pie behaviour) and skip of_platform_populate (Pie DT has audio devices as top-level nodes).
Idempotent."""
import os, sys
p = os.path.expanduser('~/s8rom/kernel/t830_q/drivers/soc/qcom/qdsp6v2/apr.c')
s = open(p).read()
if 'apr_common_init' in s:
    print('already patched'); sys.exit(0)

def sub(old, new):
    global s
    assert s.count(old) == 1, f'anchor not unique/missing: {old[:60]!r}'
    s = s.replace(old, new, 1)

# 1. child population only when the Q-style DT node exists
sub('''static void apr_add_child_devices(struct work_struct *work)
{
	int ret;

''', '''static void apr_add_child_devices(struct work_struct *work)
{
	int ret;

	if (!apr_dev_ptr)	/* legacy (Pie) DT: audio devices are top-level nodes */
		return;
''')

# 2. probe body -> apr_common_init(dev), shared by probe and the legacy path
sub('''static int apr_probe(struct platform_device *pdev)
{
	int i, j, k;
''', '''static int apr_common_init(struct device *dev)
{
	int i, j, k;
''')
sub('''	apr_dev_ptr = &pdev->dev;
	INIT_DELAYED_WORK(&add_chld_dev_work, apr_add_child_devices);
	return 0;
}
''', '''	apr_dev_ptr = dev;
	INIT_DELAYED_WORK(&add_chld_dev_work, apr_add_child_devices);
	return 0;
}

static int apr_probe(struct platform_device *pdev)
{
	return apr_common_init(&pdev->dev);
}
''')

# 3. legacy path at init time when the DT has no qcom,msm-audio-apr node
sub('''static int __init apr_init(void)
{
	platform_driver_register(&apr_driver);
	apr_dummy_init();
	return 0;
}''', '''static int __init apr_init(void)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, "qcom,msm-audio-apr");

	if (np) {
		of_node_put(np);
		platform_driver_register(&apr_driver);
	} else {
		pr_info("%s: no qcom,msm-audio-apr DT node, legacy (Pie DT) init\\n", __func__);
		apr_common_init(NULL);
	}
	apr_dummy_init();
	return 0;
}''')

# 4. cleanup only unregisters what was registered (harmless either way, keep exit symmetric)
open(p, 'w').write(s)
print('patched', p)
