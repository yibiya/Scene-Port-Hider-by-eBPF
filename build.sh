#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/system/bin"

ANDROID_API="${ANDROID_API:-26}"
ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"
LIBBPF_SRC="${LIBBPF_SRC:-}"
BPF_CC="${BPF_CC:-clang}"
BPFTOOL="${BPFTOOL:-${BPFOOL:-bpftool}}"
TARGET_CC="${TARGET_CC:-}"
VMLINUX_H="${VMLINUX_H:-$SRC/vmlinux.h}"
EXTRA_LDLIBS="${EXTRA_LDLIBS:-}"

if [[ -z "$ANDROID_NDK" ]]; then
    echo "Set ANDROID_NDK or ANDROID_NDK_HOME to your Android NDK path." >&2
    exit 1
fi

if [[ -z "$LIBBPF_SRC" ]]; then
    echo "Set LIBBPF_SRC to a libbpf checkout/build directory." >&2
    exit 1
fi

if [[ ! -f "$VMLINUX_H" ]]; then
    echo "Missing $VMLINUX_H. Generate it from the target device BTF first." >&2
    exit 1
fi

if [[ -z "$TARGET_CC" ]]; then
    HOST_TAG="linux-x86_64"
    case "$(uname -s)" in
        Darwin) HOST_TAG="darwin-x86_64" ;;
        MINGW*|MSYS*|CYGWIN*) HOST_TAG="windows-x86_64" ;;
    esac
    TARGET_CC="$ANDROID_NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android${ANDROID_API}-clang"
fi

LIBBPF_HEADERS="${LIBBPF_HEADERS:-}"
if [[ -z "$LIBBPF_HEADERS" ]]; then
    for candidate in \
        "$LIBBPF_SRC/include" \
        "$LIBBPF_SRC/src/root/usr/include" \
        "$LIBBPF_SRC/root/usr/include"; do
        if [[ -f "$candidate/bpf/bpf_core_read.h" ]]; then
            LIBBPF_HEADERS="$candidate"
            break
        fi
    done
fi

if [[ -z "$LIBBPF_HEADERS" || ! -f "$LIBBPF_HEADERS/bpf/bpf_core_read.h" ]]; then
    echo "Could not find libbpf headers." >&2
    echo "Set LIBBPF_HEADERS to a directory containing bpf/bpf_core_read.h." >&2
    echo "Current LIBBPF_SRC=$LIBBPF_SRC" >&2
    exit 1
fi

LIBBPF_LIBDIR="${LIBBPF_LIBDIR:-$LIBBPF_SRC/src}"

mkdir -p "$OUT"

# Handle embedded BTF
EMBED_BTF_FLAG=""
BTF_FILE=""
if [[ -f "$ROOT/btf/vmlinux.btf" ]]; then
    BTF_FILE="btf/vmlinux.btf"
elif [[ -f "$ROOT/vmlinux.btf" ]]; then
    mkdir -p "$ROOT/btf"
    cp "$ROOT/vmlinux.btf" "$ROOT/btf/vmlinux.btf"
    BTF_FILE="btf/vmlinux.btf"
fi

if [[ -n "$BTF_FILE" ]]; then
    echo "Found vmlinux.btf, generating embedded BTF header..."
    (cd "$ROOT" && xxd -i "$BTF_FILE") > "$SRC/vmlinux_btf.h"
    EMBED_BTF_FLAG="-DUSE_EMBEDDED_BTF"
fi

"$BPF_CC" -target bpf -D__TARGET_ARCH_arm64 -g -O2 \
    -I"$SRC" \
    -I"$LIBBPF_HEADERS" \
    -c "$SRC/hideport.bpf.c" \
    -o "$OUT/hideport.bpf.o"

"$BPFTOOL" gen skeleton "$OUT/hideport.bpf.o" > "$SRC/hideport.skel.h"

"$TARGET_CC" -O2 -Wall -Wextra -static \
    ${EMBED_BTF_FLAG:-} \
    -I"$SRC" \
    -I"$LIBBPF_HEADERS" \
    -L"$LIBBPF_LIBDIR" \
    -o "$OUT/hideport_loader" \
    "$SRC/hideport_loader.c" \
    "$SRC/tls_align.S" \
    -lbpf -lelf -lz $EXTRA_LDLIBS

chmod 0755 "$OUT/hideport_loader" 2>/dev/null || \
    echo "Warning: could not chmod $OUT/hideport_loader; this is normal on some /mnt/* WSL mounts."
echo "Built $OUT/hideport_loader and $OUT/hideport.bpf.o"
