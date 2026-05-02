#!/system/bin/sh

MODDIR=${0%/*}
CONF="$MODDIR/hideport.conf"
LOADER="$MODDIR/system/bin/hideport_loader"
LOG="$MODDIR/hideport.log"
PIDFILE="/dev/hideport_loader.pid"
LOCKDIR="/dev/hideport_loader.lock"

PKG="com.omarea.vtools"
PORTS="8788 8765"
ENABLE_EBPF=1
WAIT_FOR_PROCESS=0

[ -f "$CONF" ] && . "$CONF"
START_CONTEXT="${1:-manual}"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG"
}

is_running() {
    [ -f "$PIDFILE" ] || return 1
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    sleep 2
    if is_running; then
        log_msg "$START_CONTEXT" "hideport_loader is already running"
        exit 0
    fi
    log_msg "$START_CONTEXT" "another hideport_loader start is in progress"
    exit 0
fi

cleanup_lock() {
    rmdir "$LOCKDIR" 2>/dev/null
}

trap cleanup_lock EXIT INT TERM

get_app_uid() {
    local uid

    uid="$(stat -c "%u" "/data/data/$PKG" 2>/dev/null)"
    if [ -n "$uid" ]; then
        echo "$uid"
        return 0
    fi

    uid="$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
    if [ -n "$uid" ]; then
        echo "$uid"
        return 0
    fi

    return 1
}

wait_for_uid() {
    local uid
    local i=0

    while [ "$i" -lt 180 ]; do
        uid="$(get_app_uid)"
        if [ -n "$uid" ]; then
            echo "$uid"
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done

    return 1
}

wait_for_process_if_requested() {
    [ "$WAIT_FOR_PROCESS" = "1" ] || return 0

    while ! pidof "$PKG" >/dev/null 2>&1; do
        sleep 1
    done
    sleep 3
}

if [ "$ENABLE_EBPF" != "1" ]; then
    log_msg "$START_CONTEXT" "eBPF loader disabled by config"
    exit 0
fi

if is_running; then
    log_msg "$START_CONTEXT" "hideport_loader is already running"
    exit 0
fi

if [ ! -x "$LOADER" ]; then
    log_msg "$START_CONTEXT" "missing executable: $LOADER"
    exit 1
fi

APP_UID="$(wait_for_uid)"
if [ -z "$APP_UID" ]; then
    log_msg "$START_CONTEXT" "failed to resolve UID for package $PKG"
    exit 1
fi

wait_for_process_if_requested

BTF="$MODDIR/btf/vmlinux.btf"
[ -f "$MODDIR/vmlinux.btf" ] && BTF="$MODDIR/vmlinux.btf"

ARGS=""
if [ -f "$BTF" ]; then
    ARGS="$ARGS --btf $BTF"
fi

for port in $PORTS; do
    ARGS="$ARGS --port $port"
done
ARGS="$ARGS --uid $APP_UID"

log_msg "$START_CONTEXT" "starting hideport_loader for package $PKG uid $APP_UID ports $PORTS"
"$LOADER" $ARGS >> "$LOG" 2>&1 &
echo "$!" > "$PIDFILE"
