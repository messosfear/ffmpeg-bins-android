#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --ndk /path/to/android-ndk --api <api-level>
Downloads/clones FFmpeg and cross-compiles a static ffmpeg binary for Android aarch64.

Options:
  --ndk   Path to Android NDK root (required)
  --api   Android API level (default: 21)
EOF
  exit 1
}

NDK=""
API=21

while [ $# -gt 0 ]; do
  case "$1" in
    --ndk) NDK="$2"; shift 2 ;;
    --api) API="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

if [ -z "$NDK" ]; then
  echo "ERROR: --ndk is required"
  usage
fi

# Variables
TARGET_TRIPLE="aarch64-linux-android"
API_LEVEL="${API}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"
BUILD_DIR="$(pwd)/ffmpeg-android-build"
PREFIX="$(pwd)/android-aarch64"
FFMPEG_SRC_DIR="${BUILD_DIR}/ffmpeg"

mkdir -p "$BUILD_DIR"
mkdir -p "$PREFIX/bin"

# Compiler toolchain
CC="$TOOLCHAIN/bin/${TARGET_TRIPLE}${API_LEVEL}-clang"
CXX="$TOOLCHAIN/bin/${TARGET_TRIPLE}${API_LEVEL}-clang++"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
STRIP="$TOOLCHAIN/bin/llvm-strip"

export PATH="$TOOLCHAIN/bin:$PATH"

echo "Using:"
echo "  NDK: $NDK"
echo "  Sysroot: $SYSROOT"
echo "  CC: $CC"
echo "  API: $API_LEVEL"
echo "  Prefix: $PREFIX"
echo ""

# Clone FFmpeg (shallow)
if [ ! -d "$FFMPEG_SRC_DIR" ]; then
  git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_SRC_DIR"
fi

cd "$FFMPEG_SRC_DIR"

# Clean previous builds if any
make distclean || true

# Configure flags
CFLAGS="-O3 -fPIC -ffunction-sections -fdata-sections -march=armv8-a"
LDFLAGS="-Wl,--gc-sections"

PKG_CONFIG=
# If you need pkg-config from host, configure PKG_CONFIG path. For pure static FFmpeg (no external libs) it's not needed.

./configure \
  --prefix="$PREFIX" \
  --target-os=android \
  --arch=aarch64 \
  --cpu=generic \
  --cc="$CC" \
  --cxx="$CXX" \
  --ar="$AR" \
  --ranlib="$RANLIB" \
  --nm="$(which llvm-nm 2>/dev/null || true)" \
  --strip="$STRIP" \
  --sysroot="$SYSROOT" \
  --enable-cross-compile \
  --cross-prefix="" \
  --extra-cflags="$CFLAGS" \
  --extra-ldflags="$LDFLAGS" \
  --disable-shared \
  --enable-static \
  --disable-doc \
  --disable-debug \
  --enable-small \
  --disable-programs=no \ # keep programs (ffmpeg, ffprobe) enabled
  --disable-ffplay \
  --disable-network \
  --disable-iconv \
  --disable-postproc \
  --disable-avdevice \
  --disable-swresample \
  --disable-swscale \
  --disable-symver \
  --disable-bsfs \
  --disable-parsers \
  --disable-demuxers \
  --disable-muxers \
  --disable-encoders \
  --disable-decoders \
  --disable-decklink \
  --enable-protocol=file

# Note:
# The above disables many components to keep the binary small. Remove --disable-* lines
# for features you need (decoders/encoders/demuxers/muxers). By default ffmpeg builds many
# components; adjust to your needs.

# Build
make -j"$(nproc)"
make install

# Ensure binary exists
if [ ! -x "$PREFIX/bin/ffmpeg" ]; then
  echo "ERROR: ffmpeg binary not found at $PREFIX/bin/ffmpeg"
  exit 2
fi

# Strip binary to reduce size
"$STRIP" --strip-unneeded "$PREFIX/bin/ffmpeg" || true

echo "Built ffmpeg at: $PREFIX/bin/ffmpeg"
