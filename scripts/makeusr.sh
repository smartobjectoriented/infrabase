#!/usr/bin/env bash
#
# Standalone cmake+make build for the Linux user space, meant to be run from
# inside linux/usr. It reproduces what the usr-linux recipe does in do_build,
# so the apps and the out-of-tree kernel modules can be rebuilt quickly
# without invoking bitbake.
#
# The user-space toolchain comes from the buildroot host tree; the kernel
# modules are built against linux/linux with the kernel's own cross compiler.
#
# Copyright (c) 2026 Daniel Rossier, REDS Institute - HEIG-VD
#

# Release banner, once per invocation (see scripts/common/banner.sh).
. "$(cd "$(dirname "$(command -v -- "$0")")" && pwd)/common/banner.sh"

set -euo pipefail

# The script operates on the *current directory* (so it can live in ~/scripts),
# which must be linux/usr. The repo root is two levels up (…/usr -> … -> root).

USR_DIR="$PWD"
REPO_ROOT="$(cd "${USR_DIR}/../.." && pwd)"
BUILD_DIR="${USR_DIR}/build"

PARENT="$(basename "$(dirname "${USR_DIR}")")"

if [ "${PARENT}" != "linux" ]; then
	echo "Run this from linux/usr (current: ${USR_DIR})" >&2
	exit 1
fi

if [ ! -f "${USR_DIR}/CMakeLists.txt" ]; then
	echo "No CMakeLists.txt in ${USR_DIR} — not a usr/ directory." >&2
	exit 1
fi

# Defaults.

BUILD_TYPE="${IB_USR_BUILD_TYPE:-Debug}"
PLATFORM=""
DO_CLEAN=0
RECONFIGURE=0
SKIP_MODULES=0
CORES="$(nproc)"

usage() {
	cat <<EOF
Usage: makeusr.sh [options]   (run from linux/usr)

Options:
  -t, --type <Debug|Release> CMake build type (default: ${BUILD_TYPE})
  -p, --platform <name>      IB_PLATFORM for kernel modules (default: virt64)
  -c, --reconfigure          Force a fresh cmake configure step
  -M, --no-modules           Skip the kernel-module build
  -C, --clean                Remove build/ and exit
  -j, --jobs <N>             Parallel make jobs (default: ${CORES})
  -h, --help                 This help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-t|--type)        BUILD_TYPE="$2"; shift 2 ;;
		-p|--platform)    PLATFORM="$2"; shift 2 ;;
		-c|--reconfigure) RECONFIGURE=1; shift ;;
		-M|--no-modules)  SKIP_MODULES=1; shift ;;
		-C|--clean)       DO_CLEAN=1; shift ;;
		-j|--jobs)        CORES="$2"; shift 2 ;;
		-h|--help)        usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
	esac
done

if [ "${DO_CLEAN}" = "1" ]; then
	echo "Removing ${BUILD_DIR}"

	rm -rf "${BUILD_DIR}"
	exit 0
fi

toolchain_file="${REPO_ROOT}/linux/rootfs/host/share/buildroot/toolchainfile.cmake"
kernel_path="${REPO_ROOT}/linux/linux"

if [ ! -f "${toolchain_file}" ]; then
	echo "Buildroot toolchain missing: ${toolchain_file}" >&2
	echo "Build the rootfs/toolchain first via bitbake." >&2
	exit 1
fi

# User apps: cmake + make. The buildroot toolchain file pins absolute
# compiler paths, so no PATH tweak is needed here.

mkdir -p "${BUILD_DIR}"; cd "${BUILD_DIR}"

if [ "${RECONFIGURE}" = "1" ] || [ ! -f "${BUILD_DIR}/CMakeCache.txt" ]; then
	cmake -Wno-dev --no-warn-unused-cli \
		-DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
		-DCMAKE_KERNEL_PATH="${kernel_path}" \
		-DCMAKE_TOOLCHAIN_FILE="${toolchain_file}" \
		"${USR_DIR}"
fi
make -j"${CORES}"

# Out-of-tree kernel modules (best effort), mirroring usr-linux
# do_build:prepend's `make -C linux M=src/modules modules IB_PLATFORM=...`.
# The kernel Makefile is patched with ARCH and CROSS_COMPILE defaults
# (e.g. aarch64-none-linux-gnu-), so — exactly like the recipe — we pass
# neither and let the kernel toolchain resolve from PATH. Do NOT force a
# CROSS_COMPILE from the buildroot host tree: that is the *userspace*
# toolchain and may differ from the one the kernel was built with.

mod_dir="${USR_DIR}/src/modules"

if [ "${SKIP_MODULES}" = "0" ] && [ -d "${mod_dir}" ]; then

	if [ -f "${kernel_path}/Module.symvers" ]; then

		# IB_PLATFORM selects the module set (see src/modules/Makefile).

		plat="${PLATFORM}"

		if [ -z "${plat}" ]; then
			plat="$(grep -E '^[[:space:]]*IB_PLATFORM[[:space:]]*[?:]?=' \
				"${REPO_ROOT}/build/conf/local.conf" 2>/dev/null \
				| grep -v '^[[:space:]]*#' | tail -1 \
				| sed -E 's/.*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/')"
			plat="${plat:-virt64}"
		fi

		# Sanity-check the kernel's cross compiler is reachable on PATH.

		kcross="$(sed -nE 's/^CROSS_COMPILE[[:space:]]*[?:]?=[[:space:]]*([^[:space:]]+).*/\1/p' \
			"${kernel_path}/Makefile" | head -1)"

		if [ -n "${kcross}" ] && ! command -v "${kcross}gcc" >/dev/null 2>&1; then
			echo "WARN: kernel cross compiler '${kcross}gcc' not on PATH; skipping modules." >&2
		else
			echo "Building kernel modules (IB_PLATFORM=${plat})"

			make -C "${kernel_path}" M="${mod_dir}" modules IB_PLATFORM="${plat}"
		fi
	else
		echo "WARN: ${kernel_path}/Module.symvers missing; kernel not built."
		echo "      Skipping kernel modules (build the kernel via bitbake first)."
	fi
fi

# Local deploy == do_install_apps: hello + *.ko into build/deploy/root.

deploy="${BUILD_DIR}/deploy/root"
mkdir -p "${deploy}"
cp "${BUILD_DIR}"/src/examples/hello "${deploy}/" 2>/dev/null || true
cp "${mod_dir}"/*.ko "${deploy}/" 2>/dev/null || true

echo
echo "Done. Built linux/usr (${BUILD_TYPE}) -> ${BUILD_DIR}/deploy"
