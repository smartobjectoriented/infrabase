# Infrabase

Infrabase is a lightweight build and deployment environment for embedded systems
development. It builds a **minimal Linux system** — bootloader, kernel, root
filesystem and user-space applications — for real boards and for QEMU-emulated
ones, and deploys it to an SD-card image or to a real device.

It builds four components — **ATF**, **OP-TEE**, **AVZ** and **Linux** — and
lets you combine them: Linux standalone or as a guest of the AVZ hypervisor,
on a firmware chain with or without ATF and with or without a secure world. See [What gets built](#what-gets-built) below.

It is driven by [BitBake](https://docs.yoctoproject.org/bitbake), the task
orchestrator behind Yocto, but stays deliberately small: components are fetched
from upstream and patched from tracked patchsets, the root filesystem comes from
buildroot rather than a full distribution, and a handful of shell scripts in
`scripts/` cover the day-to-day loop.

📖 **[Sphinx documentation](https://smartobjectoriented.github.io/infrabase/index.html)** —
start with the [user guide](https://smartobjectoriented.github.io/infrabase/user_guide.html);
it is also in `doc/` and builds with `make -C doc html`.

## Quick start

The build environment ships as a container image, which is the recommended way
to build: it carries the cross toolchain and every host package, so nothing has
to be installed on your machine. The repository stays on the host and is bind-mounted,
and the build runs as *you*, so no artefact comes back root-owned.

```sh
scripts/dbuild.sh --build                # build the image, once
scripts/dbuild.sh build.sh bsp-linux     # build the Linux BSP
scripts/dbuild.sh deploy.sh bsp-linux    # deploy it to the storage image
. ./env.sh && st.sh                      # run it under QEMU (host side)
```

To build directly on the host instead, source the environment first — it puts
`scripts/` and `bitbake` on your `PATH`:

```sh
. ./env.sh
build.sh -l                              # list every recipe
build.sh bsp-linux                       # build (also bootstraps QEMU if needed)
deploy.sh bsp-linux                      # deploy
st.sh                                    # run, headless (serial on stdio)
st.sh -d                                 # run, with a graphical display
```

Host prerequisites are the package list in
[`docker/build-env/packages.txt`](docker/build-env/packages.txt) plus the
`aarch64-none-linux-gnu` toolchain; see the user guide.

## Target platforms

The platform is selected with `IB_PLATFORM` in `build/conf/local.conf`:

| `IB_PLATFORM` | Target |
|---|---|
| `virt64` | QEMU `virt`, 64-bit (aarch64) — the default |
| `virt32` | QEMU `virt`, 32-bit (arm) |
| `rpi4_64` | Raspberry Pi 4, 64-bit |
| `rpi4` | Raspberry Pi 4, 32-bit |
| `verdin-imx8mp` | Toradex Verdin iMX8M Plus (TEZI network install) |
| `x86-qemu` | QEMU x86 |

## What gets built

One variable in `build/conf/local.conf`, **`IB_BOOT_CHAIN`**, decides which of
the four components end up in an image: the stages that run before Linux, in the
order they run, joined by `+` — `atf`, `optee`, `uboot`, `avz`, `mcuboot`. So
`uboot` is Linux on a bare U-Boot, `atf+optee+uboot` adds a secure world,
`uboot+avz` runs Linux as a guest of the AVZ hypervisor, and
`atf+optee+uboot+avz` has both. Everything else (`IB_HYPERVISOR`, the ITS, which
recipes are built) is derived from it, and the order is checked.

What each platform can run is a set of stages (`IB_BOOT_STAGES_SUPPORTED`):

| Platform | Supported stages |
|---|---|
| `virt64` | `atf optee uboot avz mcuboot` |
| `verdin-imx8mp` | `atf optee uboot avz` (`atf` required) |
| `rpi4_64` | `atf uboot avz` |
| `rpi4`, `virt32`, `x86-qemu` | `uboot` |

A missing stage is a hardware or upstream limit, not an omission — the i.MX8MP
boot ROM always installs BL31, TF-A's `rpi4` port is AArch64-only, OP-TEE has no
`plat-rpi4` upstream (and the BCM2711 has no secure memory controller, so a TEE
there could never be real), and AVZ ships aarch64 defconfigs only. Each is
explained next to `IB_BOOT_STAGES_SUPPORTED` in `build/conf/local.conf`, and
asking for a stage a platform cannot run is refused at parse time rather than
producing a board that boots nothing.

## Layout

```
env.sh                  source this first
scripts/                the day-to-day scripts (build, deploy, run, mount, …)
docker/build-env/       the container build environment used by dbuild.sh
build/conf/local.conf   THE configuration file (all IB_* variables)
build/meta*/            the BitBake layers (tracked — do not delete build/)
build/tmp/              generated; safe to remove for a clean slate
linux/ u-boot/ qemu/    component trees, fetched and patched by the build
atf/ atf/optee/ avz/    ditto for ATF, OP-TEE and the AVZ hypervisor
filesystem/             storage images and the mounted partitions (p1, p2)
doc/                    this documentation (Sphinx)
```

## Releases

Infrabase uses a branch-per-release model, the same as SO3: development happens
on `main`, and every minor version gets a long-lived `release/vX.Y` maintenance
branch on which patch releases are tagged (`vX.Y.Z`, or `vX.Y.Z-rc` for
candidates). Each tag has a matching
[GitHub Release](https://github.com/smartobjectoriented/infrabase/releases).
Every script prints the release it belongs to when it starts
(`[infrabase v1.0.0] build.sh bsp-linux`); `scripts/ibversion.sh` prints it on
its own.

The full procedure — cutting patch and minor releases, tagging and publishing —
is documented in
[Release process](https://smartobjectoriented.github.io/infrabase/release_process.html).

### Maintenance branches

Each minor line has its own long-lived branch. Bug fixes for a published version
land there and are tagged as patch releases.

| Line | Branch | Latest release | Status |
|------|--------|----------------|--------|
| 1.0  | [`release/v1.0`](https://github.com/smartobjectoriented/infrabase/tree/release/v1.0) | [v1.0.0](https://github.com/smartobjectoriented/infrabase/releases/tag/v1.0.0) | Current stable |

See all versions on the
[Releases page](https://github.com/smartobjectoriented/infrabase/releases).

## Contributing

Work on a branch, one topic per branch, and open a pull request; see the
[development flow](https://smartobjectoriented.github.io/infrabase/dev_flow.html) and the
[coding conventions](https://smartobjectoriented.github.io/infrabase/coding_conventions.html).

Licensed under the GNU General Public License v2 — see [LICENSE](LICENSE).
