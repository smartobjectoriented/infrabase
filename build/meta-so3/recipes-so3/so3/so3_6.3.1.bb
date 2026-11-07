# Copyright (c) 2025-2026 EDGEMTech SA

SUMMARY = "SO3 kernel"
DESCRIPTION = "Smart Object Oriented Operating System"
LICENSE = "GPLv2"

inherit so3

# Version and revision

PR = "r0"
PV = "6.3.1"

# :append (not +=) so no space is inserted before ":so3" — otherwise the
# preceding CPU token parses as "arm "/"aarch64 " and :<cpu> overrides
# stop matching. See usr-so3_1.0.bb for the full rationale.

OVERRIDES:append = ":so3"

# Where the working directory will be placed in infrabase root dir

IB_TARGET = "${IB_SO3_PATH}"

# Infrabase does not embed the SO3 sources. Same revision as the AVZ recipe:
# both are the same kernel tree, and move together.

IB_SO3_TAG = "v6.3.1+so3#334"
SRC_URI = "git://github.com/smartobjectoriented/so3.git;nobranch=1;protocol=https"
SRCREV = "f09b674d360da6979fc416cc56c9b43899baf5e5"

# Stamps carry no signature hash: key them on SRCREV and the patch set so a
# change of either refreshes the so3/ tree.

do_fetch[stamp-extra-info] = "${SRCREV}"
do_fetch[prefuncs] += "ib_drop_stale_stamps"
do_patch[prefuncs] += "ib_drop_stale_stamps"

python () {
    d.setVarFlag('do_patch', 'stamp-extra-info', ib_patchset_digest(d))
}

python do_handle_fetch_git() {

    import os
    import subprocess

    # gitdir/so3 holds so3/ (kernel), usr/ and rootfs/, and IB_SO3_PATH must
    # contain all three: so3, usr-so3 and rootfs-so3 each build one of them.

    gitdir = os.path.join(d.getVar('WORKDIR'), 'git')
    dst_dir = d.getVar('S')

    cmd = f"find . -not -path '*/.git/*' -and \( -type f -or -type d -empty \) -exec cp -r --parents -t {dst_dir} {{}} +"
    result = subprocess.run(cmd, shell=True, check=True, cwd=os.path.join(gitdir, "so3"))
}

do_configure[nostamp] = "1"
do_configure () {
	cd ${IB_SO3_PATH}/so3

	# The kernel is built in place: distclean when the arch changes, or
	# stale objects would produce a wrong-arch kernel.

	_arch_marker=".ib_last_arch"
	if [ -f "$_arch_marker" ] && [ "$(cat $_arch_marker)" != "${IB_PLAT_CPU}" ]; then
		echo "SO3 arch changed ($(cat $_arch_marker) -> ${IB_PLAT_CPU}); running make distclean"
		make distclean
	fi

	make ${IB_CONFIG}

	echo "${IB_PLAT_CPU}" > "$_arch_marker"
}

do_build[nostamp] = "1"
do_build () {
	echo "Building SO3..."

	# The tree sits inside this repository: without a ceiling, the banner
	# version would come from a git tag of Infrabase rather than from the
	# fallback version.h carries for a tree with no git metadata.

	export GIT_CEILING_DIRECTORIES="${IB_DIR}"

	cd ${IB_SO3_PATH}/so3
	make
}

do_clean[nostamp] = "1"
do_clean () {
	rm -f ${TMPDIR}/stamps/so3*
}
addtask do_clean
