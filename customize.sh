#!/system/bin/sh

SKIPUNZIP=0

calc_sha256() {
    local file="$1"
    local line

    if command -v sha256sum >/dev/null 2>&1; then
        line="$(sha256sum "$file" 2>/dev/null)" || return 1
    elif command -v toybox >/dev/null 2>&1; then
        line="$(toybox sha256sum "$file" 2>/dev/null)" || return 1
    elif command -v busybox >/dev/null 2>&1; then
        line="$(busybox sha256sum "$file" 2>/dev/null)" || return 1
    else
        return 1
    fi

    echo "${line%% *}"
}

check_kernel_btf() {
    local expected_file="$MODPATH/kernel_btf.sha256"
    local tmp_expected="${TMPDIR:-/dev}/hideSceneport_kernel_btf.sha256"
    local current_btf="/sys/kernel/btf/vmlinux"
    local expected
    local actual

    if [ ! -f "$expected_file" ] && [ -n "$ZIPFILE" ] && command -v unzip >/dev/null 2>&1; then
        if unzip -p "$ZIPFILE" kernel_btf.sha256 > "$tmp_expected" 2>/dev/null; then
            expected_file="$tmp_expected"
        fi
    fi

    if [ ! -f "$expected_file" ]; then
        ui_print "- No kernel BTF fingerprint found; skip anti-misflash check"
        return 0
    fi

    read -r expected < "$expected_file"
    if [ -z "$expected" ]; then
        abort "! Empty kernel BTF fingerprint in module package"
    fi

    if [ ! -r "$current_btf" ]; then
        ui_print "- System BTF not found; will use embedded BTF fallback if available"
        return 0
    fi

    actual="$(calc_sha256 "$current_btf")" || abort "! Failed to calculate current kernel BTF fingerprint"

    ui_print "- Expected kernel BTF: $expected"
    ui_print "- Current  kernel BTF: $actual"

    if [ "$expected" != "$actual" ]; then
        abort "! Kernel BTF mismatch. This module was built for another kernel/device."
    fi

    ui_print "- Kernel BTF matched"
}

on_install() {
    ui_print "- Installing Scene Port Hider by eBPF"
    check_kernel_btf
    ui_print "- Edit hideport.conf if your package or ports differ"
}

set_permissions() {
    set_perm_recursive "$MODPATH" 0 0 0755 0644
    set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
    set_perm "$MODPATH/service.sh" 0 0 0755
    set_perm "$MODPATH/hideport_start.sh" 0 0 0755
    set_perm "$MODPATH/hide_scene_port.sh" 0 0 0755
    set_perm "$MODPATH/service.d/hide_scene_port.sh" 0 0 0755
    set_perm "$MODPATH/system/bin/hideport_loader" 0 0 0755
}
