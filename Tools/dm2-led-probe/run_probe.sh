#!/bin/sh
# Runs dm2-led-probe while capturing the kernel USB log, and writes both to one report file.
# Usage: ./run_probe.sh [--capture]      (--capture needs sudo: sudo ./run_probe.sh --capture)
cd "$(dirname "$0")"
[ -x ./dm2-led-probe ] || ./build.sh || exit 1
report="probe-report-$(date +%Y%m%d-%H%M%S).txt"
klog="$(mktemp -t dm2klog)"

log stream --style compact --level debug \
	--predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "usb" OR eventMessage CONTAINS[c] "xhci" OR eventMessage CONTAINS[c] "endpoint" OR eventMessage CONTAINS[c] "pipe" OR eventMessage CONTAINS[c] "catalog" OR eventMessage CONTAINS[c] "entitle" OR eventMessage CONTAINS[c] "personalit" OR eventMessage CONTAINS[c] "MergeProperties" OR eventMessage CONTAINS[c] "0665")' \
	> "$klog" 2>&1 &
logpid=$!
sleep 1

./dm2-led-probe "$@" 2>&1 | tee "$report"

sleep 1
kill "$logpid" 2>/dev/null
wait "$logpid" 2>/dev/null
{
	echo
	echo "===== kernel USB log during the run ====="
	cat "$klog"
} >> "$report"
rm -f "$klog"
echo
echo "Report saved: $(pwd)/$report"
