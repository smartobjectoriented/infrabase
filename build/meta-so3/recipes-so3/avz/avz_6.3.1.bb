# Copyright (c) 2025-2026 EDGEMTech SA

SUMMARY = "AVZ Hypervisor"
DESCRIPTION = "AVZ (Agency Virtualizer) hypervisor based on the polymorphic SO3 Operating System"
LICENSE = "GPLv2"

inherit avz

# Version and revision

PR = "r0"
PV = "6.3.1"

OVERRIDES += ":avz"

# Where the working directory will be placed in infrabase root dir
IB_TARGET = "${IB_AVZ_PATH}"

# Infrabase does not embed the SO3 sources, so AVZ is FETCHED from the SO3
# repository. AVZ *is* the polymorphic SO3 kernel built with an avz
# defconfig, hence the SO3 repo as the source.
#
# Pinned to a release tag's commit, deliberately: an earlier form of this
# recipe resolved SRCREV at parse time from a local checkout
# (git:///home/.../so3;protocol=file with a `git rev-parse main` in the
# SRCREV expansion). That tied the recipe to one workstation, broke inside
# the build container, and made "which AVZ is in this image" unanswerable
# from the tree alone. Bumping AVZ is now a deliberate gesture: move SRCREV
# and IB_SO3_TAG together, in one commit.
#
# IB_SO3_TAG records the human-readable tag SRCREV corresponds to; keep the
# two in sync (git rev-parse <tag>^{commit}).

# Currently v6.3.1 plus the AVZ NR_IRQS fix, which is on main but not yet in a
# tag. AVZ's gic_handle() bounded INTIDs only against 1021 while irq_to_desc()
# indexed an array of NR_IRQS entries, and NR_IRQS was defined twice, at 160.
# BCM2711 raises up to 208 and its genet ethernet sits at 189/190 — on rpi4_64
# the agency booted to userspace and then took an EL2 data abort the moment
# the network started. smartobjectoriented/so3#334, merged 2026-09-15.
#
# Pinned to the merge commit rather than a tag because v6.3.1 predates it:
# move both lines back to a tag as soon as SO3 cuts the release that carries
# it (v6.3.2 or later) — a commit answers "which AVZ is in this image" less
# well than a tag does. Backported from opencn-ng.

IB_SO3_TAG = "v6.3.1+so3#334"
SRC_URI = "git://github.com/smartobjectoriented/so3.git;nobranch=1;protocol=https"
SRCREV = "f09b674d360da6979fc416cc56c9b43899baf5e5"

python do_handle_fetch_git() {

    import os
    import subprocess

    # Copy only the SO3 kernel: AVZ's sources live inside the kernel tree
    # and the repo nests the kernel under <root>/so3/so3, so the copy is
    # rooted at gitdir/so3/so3 rather than at the repository root.

    gitdir = os.path.join(d.getVar('WORKDIR'), 'git')
    dst_dir = d.getVar('S')

    cmd = f"find . -not -path '*/.git/*' -and \( -type f -or -type d -empty \) -exec cp -r --parents -t {dst_dir} {{}} +"
    result = subprocess.run(cmd, shell=True, check=True, cwd=os.path.join(gitdir, "so3", "so3"))
}

do_configure[nostamp] = "1"
do_configure () {
	cd ${IB_TARGET}
	make ${IB_CONFIG}
}

do_build[nostamp] = "1"
do_build () {
	bbplain "Building AVZ (${IB_CONFIG})..."

	cd ${IB_TARGET}
	make
}

do_clean[nostamp] = "1"
do_clean () {
	rm -f ${TMPDIR}/stamps/avz*
}
addtask do_clean
