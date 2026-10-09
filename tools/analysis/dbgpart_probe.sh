#!/usr/bin/env bash
# Runs ON the build server: what does Samsung's sec_debug_partition write to the 'debug' partition on panic?
cd ~/s8rom/kernel/t830_q
f=drivers/debug/sec_debug_partition.c
grep -nE 'panic_notifier|static int dbg_partition_panic|debug_partition|DEBUG_PARTITION|_OFFSET|struct debug_reset|write_debug_partition|kmsg|log_buf|SEC_DEBUG_' $f | head -40
echo "== panic notifier body:"
grep -n 'dbg_partition_panic_notifier_call\|static int dbg_partition_notifier' -A25 $f | head -40
echo "== header layout:"
grep -nE 'define .*OFFSET|define .*SIZE' include/linux/sec_debug_partition.h include/linux/qcom/sec_debug_partition.h 2>/dev/null | head -30
echo "== config:"; grep -E 'SEC_DEBUG_PARTITION|SEC_DEBUG_RESET_REASON|SEC_DEBUG_SUMMARY|SEC_LOG_LAST_KMSG|SEC_DEBUG_HIST' ~/s8rom/kernel/out_dream/.config
