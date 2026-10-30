# Copyright (C) 2006  OpenedHand LTD
# Copyright (C) 2023-2026 EDGEMTech Ltd
#
# SPDX-License-Identifier: MIT

# Point to an empty file so any user's custom settings don't break things
QUILTRCFILE ?= "${STAGING_ETCDIR_NATIVE}/quiltrc"

PATCH_GIT_USER_NAME ?= "OpenEmbedded"
PATCH_GIT_USER_EMAIL ?= "oe.patch@oe"

inherit terminal

python () {
    if d.getVar('PATCHTOOL') == 'git' and d.getVar('PATCH_COMMIT_FUNCTIONS') == '1':
        extratasks = bb.build.tasksbetween('do_unpack', 'do_patch', d)
        try:
            extratasks.remove('do_unpack')
        except ValueError:
            # For some recipes do_unpack doesn't exist, ignore it
            pass

        d.appendVarFlag('do_patch', 'prefuncs', ' patch_task_patch_prefunc')
        for task in extratasks:
            d.appendVarFlag(task, 'postfuncs', ' patch_task_postfunc')

    # Append patch_save_pristine after every other do_unpack postfunc — in
    # particular do_handle_fetch_git from base.bbclass, which is what
    # actually populates ${S} on git-fetched recipes. Done here (parse-time
    # anonymous python) so we run AFTER base.bbclass's `do_unpack[postfuncs]
    # = ...` overwrite, preserving the run order
    # handle_fetch_git → patch_save_pristine.
    d.appendVarFlag('do_unpack', 'postfuncs', ' patch_save_pristine')
}

python patch_task_patch_prefunc() {
    # Prefunc for do_patch
    srcsubdir = d.getVar('S')

    workdir = os.path.abspath(d.getVar('WORKDIR'))
    testsrcdir = os.path.abspath(srcsubdir)
    if (testsrcdir + os.sep).startswith(workdir + os.sep):
        # Double-check that either workdir or S or some directory in-between is a git repository
        found = False
        while testsrcdir != workdir:
            if os.path.exists(os.path.join(testsrcdir, '.git')):
                found = True
                break
            if testsrcdir == workdir:
                break
            testsrcdir = os.path.dirname(testsrcdir)
        if not found:
            bb.fatal('PATCHTOOL = "git" set for source tree that is not a git repository. Refusing to continue as that may result in commits being made in your metadata repository.')

    patchdir = os.path.join(srcsubdir, 'patches')
    if os.path.exists(patchdir):
        if os.listdir(patchdir):
            d.setVar('PATCH_HAS_PATCHES_DIR', '1')
        else:
            os.rmdir(patchdir)
}

python patch_task_postfunc() {
    # Prefunc for task functions between do_unpack and do_patch
    import oe.patch
    import shutil
    func = d.getVar('BB_RUNTASK')
    srcsubdir = d.getVar('S')

    if os.path.exists(srcsubdir):
        if func == 'do_patch':
            haspatches = (d.getVar('PATCH_HAS_PATCHES_DIR') == '1')
            patchdir = os.path.join(srcsubdir, 'patches')
            if os.path.exists(patchdir):
                shutil.rmtree(patchdir)
                if haspatches:
                    stdout, _ = bb.process.run('git status --porcelain patches', cwd=srcsubdir)
                    if stdout:
                        bb.process.run('git checkout patches', cwd=srcsubdir)
        stdout, _ = bb.process.run('git status --porcelain .', cwd=srcsubdir)
        if stdout:
            useroptions = []
            oe.patch.GitApplyTree.gitCommandUserOptions(useroptions, d=d)
            bb.process.run('git add .; git %s commit -a -m "Committing changes from %s\n\n%s"' % (' '.join(useroptions), func, oe.patch.GitApplyTree.ignore_commit_prefix + ' - from %s' % func), cwd=srcsubdir)
}

def src_patches(d, all=False, expand=True):
    import oe.patch
    return oe.patch.src_patches(d, all, expand)

def should_apply(parm, d):
    """Determine if we should apply the given patch"""
    import oe.patch
    return oe.patch.should_apply(parm, d)

should_apply[vardepsexclude] = "DATE SRCDATE"

python patch_do_patch() {
    import oe.patch

    patchsetmap = {
        "patch": oe.patch.PatchTree,
        "quilt": oe.patch.QuiltTree,
        "git": oe.patch.GitApplyTree,
    }

    cls = patchsetmap[d.getVar('PATCHTOOL') or 'quilt']

    resolvermap = {
        "noop": oe.patch.NOOPResolver,
        "user": oe.patch.UserResolver,
    }

    rcls = resolvermap[d.getVar('PATCHRESOLVE') or 'user']

    classes = {}

    s = d.getVar('S')

    os.putenv('PATH', d.getVar('PATH'))

    # We must use one TMPDIR per process so that the "patch" processes
    # don't generate the same temp file name.
 
    import tempfile
    process_tmpdir = tempfile.mkdtemp()
    os.environ['TMPDIR'] = process_tmpdir

    for patch in src_patches(d):
        _, _, local, _, _, parm = bb.fetch.decodeurl(patch)

        if "patchdir" in parm:
            patchdir = parm["patchdir"]
            if not os.path.isabs(patchdir):
                patchdir = os.path.join(s, patchdir)
            if not os.path.isdir(patchdir):
                bb.fatal("Target directory '%s' not found, patchdir '%s' is incorrect in patch file '%s'" %
                    (patchdir, parm["patchdir"], parm['patchname']))
        else:
            patchdir = s

        if not patchdir in classes:
            patchset = cls(patchdir, d)
            resolver = rcls(patchset, oe_terminal)
            classes[patchdir] = (patchset, resolver)
            patchset.Clean()
        else:
            patchset, resolver = classes[patchdir]

        bb.note("Applying patch '%s' (%s)" % (parm['patchname'], oe.path.format_display(local, d)))
        try:
            patchset.Import({"file":local, "strippath": parm['striplevel']}, True)
        except Exception as exc:
            bb.utils.remove(process_tmpdir, True)
            bb.fatal("Importing patch '%s' with striplevel '%s'\n%s" % (parm['patchname'], parm['striplevel'], repr(exc).replace("\\n", "\n")))
        try:
            resolver.Resolve()
        except bb.BBHandledException as e:
            bb.utils.remove(process_tmpdir, True)
            bb.fatal("Applying patch '%s' on target directory '%s'\n%s" % (parm['patchname'], patchdir, repr(e).replace("\\n", "\n")))

    bb.utils.remove(process_tmpdir, True)
    del os.environ['TMPDIR']
}
patch_do_patch[vardepsexclude] = "PATCHRESOLVE"

addtask patch after do_unpack
do_patch[dirs] = "${WORKDIR}"

def get_next_number(patchdir):
    highest_number = 0
	
    for file in os.listdir(patchdir):
        if file[:4].isdigit():
            number = int(file[:4])
            if number > highest_number:
                highest_number = number

    # Increment the highest number by one
    new_number = highest_number + 1
    
    return new_number
   
do_diffcompose[nostamp] = "1"

# Save an untouched copy of ${S} right after do_unpack (+ its
# do_handle_fetch_git postfunc) populates it, BEFORE do_patch mutates the
# tree. do_diffcompose later compares this pristine snapshot against
# IB_TARGET so that the staged patches reflect the FULL divergence of
# IB_TARGET from upstream — enabling do_updiff to consolidate per-file
# patches instead of appending an ever-growing chain.

python patch_save_pristine() {
    import os
    import shutil
    s = d.getVar('S')
    if not s or not os.path.isdir(s):
        return
    pristine = s + '.pristine'
    if os.path.isdir(pristine):
        shutil.rmtree(pristine)
    shutil.copytree(s, pristine, symlinks=True)
}

# Directory holding the recipe's numbered patchset (NNNN-${PF}/ and its
# NNNN-${PF}-patches.inc), where do_diffcompose stages and do_updiff merges.
# Defaults to the recipe's own files/. A bbappend that carries the patchset
# in its own layer directory must point it there (with :=, so THISDIR is the
# bbappend's): otherwise updiff never sees the existing patches and builds a
# second, unused patchset next to the base recipe.
IB_PATCHSET_DIR ??= "${FILE_DIRNAME}/files"

# Infrabase patch generation algorithm
#
# Produces per-file patches in ${IB_PATCHSET_DIR}/${PF}/ comparing the
# pristine upstream sources (${S}.pristine, saved by patch_save_pristine
# right after do_unpack) against the local working tree (IB_TARGET). Each
# staged patch is therefore a self-contained "upstream → final" diff for
# one source file; do_updiff can drop it in place at the slot of the
# existing patch for that file, fully replacing the previous content.
#
# Patch headers use git-style "a/<rel>" / "b/<rel>" labels so the resulting
# patches apply cleanly with `patch -p1` from the source tree root,
# independent of where the project was checked out.  Earlier versions of
# this task wrote absolute paths on both sides (e.g. /home/.../<user>/.../),
# which silently broke as soon as the repository was cloned anywhere else.
#
# The staging directory ${IB_PATCHSET_DIR}/${PF}/ is wiped and recreated
# on every run so that stale patches from previous invocations do not leak
# into the new patchset (do_updiff promotes this directory in place into
# the existing numbered patchset).

python patch_do_diffcompose() {
    import os
    import re
    import fnmatch
    import shlex
    import shutil
    import subprocess

    source_dir = d.getVar('S') + '.pristine'
    if not os.path.isdir(source_dir):
        bb.fatal(
            f"do_diffcompose: pristine source {source_dir} missing. "
            f"Run './scripts/build.sh -xc {d.getVar('PN')}' first so that "
            f"do_unpack regenerates the pristine snapshot, then re-run updiff."
        )
    target_dir = d.getVar('IB_TARGET')
    output_dir = os.path.join(d.getVar('IB_PATCHSET_DIR'), d.getVar('PF'))

    if os.path.isdir(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)

    diff_files_tmp = os.path.join(d.getVar('TMPDIR'), "diff_files.tmp")

    # Enumerate differing/added/removed files.  cwd=target_dir so the target
    # side of each line is reported as "./<rel>".
    #
    # Excludes filter out build artefacts that leak into IB_TARGET when the
    # user runs `make` before `updiff`. Without this filter the patchset
    # gets polluted with hundreds of generated files (kconfig output, dtc
    # intermediates, kbuild auto-generated headers, etc.). Patterns are
    # matched against basenames by `diff -x`.
    exclude_patterns = [
        # compiler / linker object artefacts. NOTE: *.lds is NOT excluded —
        # SO3 ships hand-written linker scripts (e.g. arch/*/so3.lds) and
        # filtering them silently kills the corresponding source patch.
        '*.o', '*.a', '*.ko', '*.so', '*.cmd', '*.su', '*.o.d', '*.d',
        '*.mod', '*.mod.*',
        # kbuild auto-generated headers and asm. NOTE: *.lds is generated
        # only for some files (e.g. arch/arm64/kernel/module.lds.S → module.lds);
        # we cannot blacklist `*.lds` globally so individual names go below.
        'autoconf.h', 'asm-offsets.h', 'asm-offsets.s',
        'devicetable-offsets.h', 'devicetable-offsets.s',
        'elfconfig.h', 'module.lds',
        # lex / yacc / bison generated parsers — kconfig, dtc, and any other
        # consumer of flex/bison. Sources are *.l / *.y (kept); outputs are
        # *.lex.c, *.tab.c, *.tab.h (excluded).
        'lex.zconf.c', 'zconf.tab.c', 'zconf.hash.c',
        '*lex.lex.c', '*.lex.c', '*.tab.c', '*.tab.h', '*lexer.l.c',
        # kconfig output / state files
        '.config', '.config.old', 'auto.conf', 'auto.conf.cmd',
        'tristate.conf', 'config_data', 'config_data.gz', 'config_data.h',
        # generated SO3 syscall tables
        'syscall_number.h', 'syscall_table.h', 'syscall_table.h.in',
        # device-tree build outputs and intermediates (the *.tmp pattern
        # also catches the leading-dot dtc temp files such as
        # ".virt64.dtb.dts.tmp")
        '*.dtb', '*.dtbo', '*.tmp',
        # vmlinux + kallsyms-pass artefacts (`.tmp_vmlinux*.{syms,kallsyms.S}`,
        # `.vmlinux.export.c`, `.version` — the build counter file at root).
        'vmlinux*', '.vmlinux.*', '.version', '.tmp_*', '.missing-*',
        'System.map', 'Module.symvers',
        'modules.builtin', 'modules.builtin.modinfo', 'modules.order',
        # u-boot build outputs (final binaries, maps, configs)
        'u-boot', 'u-boot.cfg*', 'u-boot.sym', 'u-boot.srec',
        'u-boot.map', 'u-boot.lds', 'u-boot.bin', 'u-boot.bin.*',
        'u-boot-dtb*', 'u-boot-nodtb*',
        # u-boot kbuild-generated config + example/efi build outputs that
        # leak into IB_TARGET after a `make` (include/generated and
        # include/config are dir-excluded below; these live elsewhere).
        'autoconf.mk', 'autoconf.mk.dep', '*.srec',
        'efi_miniapp_*.h',
        # initramfs build deps
        '.initramfs_*',
    ]
    # Exclude the quilt working directory + kbuild-generated trees:
    #   patches/      — quilt staging from do_attach_infrabase
    #   include/generated/ — kbuild's auto-generated arch headers (cfi.h,
    #                       delay.h, etc. from arch/*/include/asm/Kbuild)
    #   include/config/    — kbuild's symbol-tracking files
    excludes = ' '.join(f'-x "{p}"' for p in exclude_patterns)
    excludes += ' --exclude=.git --exclude=patches'
    excludes += ' --exclude=generated --exclude=config'
    # Recipe-supplied extra excludes — space-separated directory/file
    # basenames (glob), matched by `diff --exclude` at any depth. Used for
    # things that vary per recipe and would otherwise flood the patchset,
    # most notably an out-of-tree build directory (e.g. QEMU's meson/ninja
    # `build/`, which holds 1000+ generated files). A blanket exclude in
    # this shared class would be unsafe (another recipe might ship real
    # source under such a name), so each recipe opts in via IB_UPDIFF_EXCLUDE.
    #
    # An entry holding a '/' is a path from the tree root instead (fnmatch
    # pattern), for a generated file whose basename a real source shares:
    # U-Boot's include/config.h against arch/*/include/asm/config.h. A
    # leading '/' names a file at the root itself.
    path_excludes = []
    for x in (d.getVar('IB_UPDIFF_EXCLUDE') or '').split():
        if '/' in x:
            path_excludes.append(x.lstrip('/'))
        else:
            excludes += f' --exclude={shlex.quote(x)}'
    statement = (
        f'diff -Nrq {excludes} --no-dereference '
        f'{shlex.quote(source_dir)} . > {shlex.quote(diff_files_tmp)}'
    )
    subprocess.call(statement, shell=True, cwd=target_dir)

    new_number = 1
    src_norm = source_dir.rstrip('/') + '/'

    with open(diff_files_tmp, "r") as diff_file:
        for raw_line in diff_file:
            line = raw_line.rstrip('\n')
            if not line:
                continue

            src_path = None
            tgt_path = None
            rel = None

            # Form 1: "Files <src> and <tgt> differ"
            m = re.match(r'^Files (.+) and (.+) differ$', line)
            if m:
                src_path = m.group(1)
                tgt_path = m.group(2)
                if tgt_path.startswith('./'):
                    rel = tgt_path[2:]
                elif src_path.startswith(src_norm):
                    rel = src_path[len(src_norm):]
                else:
                    bb.warn(f"do_diffcompose: cannot derive relative path for: {line}")
                    continue
            else:
                # Form 2: "Only in <dir>: <name>"
                m = re.match(r'^Only in (.+): (.+)$', line)
                if not m:
                    bb.warn(f"do_diffcompose: unrecognised diff -Nrq line: {line}")
                    continue
                only_dir = m.group(1)
                only_name = m.group(2)
                full = os.path.join(only_dir, only_name)
                if only_dir == source_dir or only_dir.startswith(src_norm):
                    # Present only in source -> file deleted in target.
                    src_path = full
                    rel = os.path.relpath(full, source_dir)
                    tgt_path = os.path.join('.', rel)
                else:
                    # only_dir is relative to cwd=target_dir; file added locally.
                    tgt_path = full
                    rel = os.path.relpath(full, '.')
                    src_path = os.path.join(source_dir, rel)

            if any(fnmatch.fnmatch(rel, p) for p in path_excludes):
                continue

            filename = os.path.basename(rel)
            output_patch = os.path.join(output_dir, f"{new_number:04d}-{filename}.patch")

            # Per-file unified diff with git-style a/<rel> b/<rel> labels so
            # the patch applies cleanly with `patch -p1` regardless of the
            # checkout location.
            cmd = [
                'diff', '--no-dereference', '-uN',
                '--label', f'a/{rel}',
                '--label', f'b/{rel}',
                src_path, tgt_path,
            ]
            with open(output_patch, 'wb') as out:
                subprocess.run(cmd, stdout=out, cwd=target_dir, check=False)

            # `diff -uN` emits "Binary files <a> and <b> differ" instead of
            # a usable hunk when either side is binary. Writing that as a
            # .patch file makes do_patch fail later with "Only garbage was
            # found in the patch input". These are typically build
            # artefacts (e.g. compiled scripts/kconfig/conf) that leaked
            # into IB_TARGET; just drop the patch and move on.
            with open(output_patch, 'rb') as f:
                first = f.readline()
            if first.startswith(b'Binary files '):
                bb.note(f"do_diffcompose: skipping binary file: {rel}")
                os.remove(output_patch)
                continue

            new_number += 1

    os.remove(diff_files_tmp)
}

def generate_src_uri(patch_directory, header=None):
    patches = sorted(p for p in os.listdir(patch_directory)
                     if p.endswith(".patch"))
    # Keep the existing .inc's leading comment block (its copyright and any
    # notes), so repeated updiff runs don't churn it; standard one otherwise.
    src_uri = header or "# Copyright (c) 2025-2026 EDGEMTech SA\n\n"
    src_uri += "SRC_URI += \"\\ \n"
    for patch in patches:
        src_uri += "    file://" + patch + " \\ \n"
    src_uri += "\"\n"
    return src_uri


def patch_identifier(path):
    """Return the relative path encoded in a patch's "--- a/<path>" or
    "+++ b/<path>" header line. Patches produced by do_diffcompose always
    carry git-style a/<rel> b/<rel> labels, so this identifier uniquely
    designates the source file the patch targets, independent of the
    patch's own filename or sequence number."""
    src = None
    dst = None
    try:
        with open(path, 'r', errors='replace') as f:
            for i, line in enumerate(f):
                if i > 8:
                    break
                if line.startswith('--- '):
                    src = line[4:].rstrip('\r\n').split('\t', 1)[0]
                elif line.startswith('+++ '):
                    dst = line[4:].rstrip('\r\n').split('\t', 1)[0]
                    break
    except OSError:
        return None
    for s in (dst, src):
        if not s or s == '/dev/null':
            continue
        if s.startswith('a/') or s.startswith('b/'):
            return s[2:]
        return s
    return None


def index_patchset(directory):
    """Build {relative_path: [patch_filename, ...]} for a patchset
    directory. The list lets callers detect when several patches in the
    series modify the same source file (a chain) and treat that case
    specially — consolidation only works when exactly one patch targets a
    given file."""
    idx = {}
    if not os.path.isdir(directory):
        return idx
    for fname in sorted(os.listdir(directory)):
        if not fname.endswith('.patch'):
            continue
        pid = patch_identifier(os.path.join(directory, fname))
        if pid is not None:
            idx.setdefault(pid, []).append(fname)
    return idx

def ib_refresh_attach_manifest(d, rels):
    """Rewrite the ${IB_TARGET}.attach.sha256 entries for the given
    relative paths with the files' current hashes: added when the file is
    new, dropped when it is gone. Other entries are kept as they are."""
    import hashlib

    target = d.getVar('IB_TARGET')
    manifest = target + '.attach.sha256'
    if not os.path.isfile(manifest):
        return

    # sha256sum lines are "<hash>  ./<rel>". A line it escaped (leading
    # backslash, for a name with a newline or backslash) is kept verbatim.
    entries = {}
    with open(manifest, 'r', errors='surrogateescape') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.startswith('\\') and len(line) > 66 and line[64:66] == '  ':
                entries[line[66:]] = line[:64]
            else:
                entries[line] = None

    for rel in rels:
        key = './' + rel
        path = os.path.join(target, rel)
        if os.path.isfile(path) and not os.path.islink(path):
            h = hashlib.sha256()
            with open(path, 'rb') as f:
                for chunk in iter(lambda: f.read(1 << 20), b''):
                    h.update(chunk)
            entries[key] = h.hexdigest()
        else:
            entries.pop(key, None)

    with open(manifest, 'w', errors='surrogateescape') as f:
        for key in sorted(entries):
            f.write(key + '\n' if entries[key] is None
                    else f"{entries[key]}  {key}\n")

addtask do_updiff
do_updiff[nostamp] = "1"

# Merge the staged patches produced by do_diffcompose
# (${IB_PATCHSET_DIR}/${PF}/, one "pristine → IB_TARGET" diff per file) back
# into the patch series the recipe actually applies.
#
# The series is read from SRC_URI (src_patches(), the very list do_patch
# applies, in order), so EVERY patchset is seen: the recipe's own files/ and
# those a bbappend brings from another directory (the course's vext layers).
# Looking at the recipe's own files/ alone made updiff blind to the bbappend
# patches: it re-appended their content to the base set, and do_patch then
# applied it twice.
#
# Each patch is split into per-file sections and indexed by target path
# (header path with the patch's striplevel removed, exactly as `patch -pN`
# does — so "./arch/x" and "b/arch/x" are the same file). For each staged
# file, given the CHAIN of series patches that touch it:
#
#   * KEEP — the chain already turns pristine into IB_TARGET's content
#     (checked by applying it on a scratch copy). Nothing is rewritten, so a
#     patch generated by another tool does not churn into an equivalent one.
#   * REWRITE — otherwise the LAST patch of the chain gets a fresh section
#     for this file, diffed against the state the earlier patches leave
#     (pristine + chain[:-1]). The earlier patches are untouched and nothing
#     is applied twice. A one-patch chain is the old "consolidate"; longer
#     chains (two patchsets on one file, or append-only history) used to be
#     refused. Other sections of a multi-file patch are kept as they are.
#   * APPEND — no patch touches the file yet: the staged diff becomes a new
#     patch at the end of the last patchset of the series whose .inc is a
#     plain generated one (the course's, for a vext bbappend), or of
#     ${IB_PATCHSET_DIR}/0001-${PF}/ when there is none.
#
# Nothing is written unless every file was resolved: if a chain no longer
# applies, updiff stops with the file named and the patchsets untouched.
# Patches whose file is not staged (unchanged since pristine, or excluded)
# are kept as they are. The .inc of a patchset is regenerated only when a
# patch was appended to it.

def ib_patch_split(path):
    """Split a patch file into (preamble, [(src, dst, text), ...]), one entry
    per file section ("--- " line directly followed by "+++ ")."""
    with open(path, 'r', errors='surrogateescape') as f:
        lines = f.readlines()
    starts = [i for i in range(len(lines) - 1)
              if lines[i].startswith('--- ') and lines[i + 1].startswith('+++ ')]
    if not starts:
        return ''.join(lines), []
    sections = []
    for n, i in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(lines)
        src = lines[i][4:].rstrip('\r\n').split('\t', 1)[0]
        dst = lines[i + 1][4:].rstrip('\r\n').split('\t', 1)[0]
        sections.append((src, dst, ''.join(lines[i:end])))
    return ''.join(lines[:starts[0]]), sections

def ib_patch_target(src, dst, strip):
    """Path a section targets once `patch -p<strip>` has stripped it."""
    for p in (dst, src):
        if not p or p == '/dev/null':
            continue
        parts = p.split('/')
        if len(parts) <= strip:
            continue
        return os.path.normpath('/'.join(parts[strip:]))
    return None

def ib_patch_series(d):
    """The patches do_patch applies, in order, split and indexed:
    (series, index) with series = [{path, strip, preamble, sections}] and
    index = {rel: [(entry, section_number), ...]} in application order."""
    series = []
    index = {}
    for url in src_patches(d):
        _, _, local, _, _, parm = bb.fetch.decodeurl(url)
        if 'patchdir' in parm:
            bb.warn(f"do_updiff: {os.path.basename(local)} uses patchdir=, "
                    "not handled; its files are ignored")
            continue
        strip = int(parm.get('striplevel', '1'))
        preamble, sections = ib_patch_split(local)
        entry = {'path': local, 'strip': strip,
                 'preamble': preamble, 'sections': sections}
        series.append(entry)
        for n, (src, dst, _) in enumerate(sections):
            rel = ib_patch_target(src, dst, strip)
            if rel:
                index.setdefault(rel, []).append((entry, n))
    return series, index

def ib_apply_chain(rel, chain, pristine, tmpdir):
    """Content of `rel` after applying `chain` (its sections for rel only)
    on top of the pristine file; None if the file does not exist then.
    Raises RuntimeError with patch's output when a section does not apply."""
    import shutil
    import subprocess
    import tempfile

    work = tempfile.mkdtemp(dir=tmpdir)
    try:
        dest = os.path.join(work, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        src = os.path.join(pristine, rel)
        if os.path.isfile(src):
            shutil.copyfile(src, dest)
        for entry, n in chain:
            sec = os.path.join(work, '.section.patch')
            with open(sec, 'w', errors='surrogateescape') as f:
                f.write(entry['sections'][n][2])
            r = subprocess.run(['patch', f"-p{entry['strip']}", '-d', work,
                                '-s', '-f', '--no-backup-if-mismatch',
                                '-r', '-', '-i', sec],
                               capture_output=True, text=True)
            os.remove(sec)
            if r.returncode != 0:
                raise RuntimeError(f"{os.path.basename(entry['path'])}: "
                                   f"{(r.stdout + r.stderr).strip()}")
        if not os.path.isfile(dest):
            return None
        with open(dest, 'rb') as f:
            return f.read()
    finally:
        shutil.rmtree(work, ignore_errors=True)

def ib_inc_is_plain(inc_path):
    """True when an .inc only holds what generate_src_uri() writes (comments,
    SRC_URI += "\\, file:// lines, closing quote), so it can be regenerated
    without losing anything."""
    import re

    if not os.path.isfile(inc_path):
        return True
    with open(inc_path) as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith('#'):
                continue
            if re.match(r'^SRC_URI \+= "\\$', s) or s == '"' \
                    or re.match(r'^file://\S+( \\)?$', s):
                continue
            return False
    return True

def ib_inc_for(setdir):
    return setdir.rstrip('/') + '-patches.inc'

python do_updiff() {
    import os
    import re
    import shutil
    import subprocess
    import tempfile

    pf = d.getVar('PF')
    target = d.getVar('IB_TARGET')
    pristine = d.getVar('S') + '.pristine'
    staging = os.path.join(d.getVar('IB_PATCHSET_DIR'), pf)

    if not os.path.isdir(staging):
        bb.fatal(f"do_updiff: staging directory {staging} not found "
                 "(run do_diffcompose first?)")

    series, index = ib_patch_series(d)
    staged = index_patchset(staging)

    # A real edit adds a handful of files. Dozens of new ones is a built tree
    # seen through an incomplete exclude list: refuse before writing anything.

    limit = int(d.getVar('IB_UPDIFF_MAX_NEW') or 20)
    new = sorted(rel for rel in staged if rel not in index)
    if len(new) > limit:
        shutil.rmtree(staging)
        bb.fatal(f"do_updiff: {len(new)} files in {target} have no patch yet "
                 f"(limit {limit}), e.g. {', '.join(new[:5])}. That is build "
                 "output taken for source: name it in IB_UPDIFF_EXCLUDE, or "
                 "raise IB_UPDIFF_MAX_NEW if the count is right. Nothing was "
                 "written.")

    # Where new patches go: the last patchset of the series with a plain
    # .inc, else the recipe's own 0001-${PF}/ (created on first use).
    append_dir = None
    for entry in reversed(series):
        setdir = os.path.dirname(entry['path'])
        if re.match(r'^\d{4}-' + re.escape(pf) + r'$', os.path.basename(setdir)) \
                and ib_inc_is_plain(ib_inc_for(setdir)):
            append_dir = setdir
            break
    if append_dir is None:
        append_dir = os.path.join(d.getVar('IB_PATCHSET_DIR'), f"0001-{pf}")

    def final_of(rel):
        path = os.path.join(target, rel)
        if os.path.isfile(path) and not os.path.islink(path):
            with open(path, 'rb') as f:
                return f.read()
        return None

    # First pass: decide everything, write nothing.
    kept, rewritten, rewrites, appends = [], [], {}, []
    tmpdir = tempfile.mkdtemp(prefix='updiff-', dir=d.getVar('TMPDIR'))
    try:
        for rel, snames in sorted(staged.items()):
            chain = index.get(rel, [])
            if not chain:
                appends.append((rel, os.path.join(staging, snames[0])))
                continue

            final = final_of(rel)
            try:
                if ib_apply_chain(rel, chain, pristine, tmpdir) == final:
                    kept.append(rel)
                    continue
                base = ib_apply_chain(rel, chain[:-1], pristine, tmpdir)
            except RuntimeError as e:
                shutil.rmtree(tmpdir, ignore_errors=True)
                bb.fatal(f"do_updiff: {rel}: the series no longer applies "
                         f"({e}). Nothing was written.")

            if base == final:
                shutil.rmtree(tmpdir, ignore_errors=True)
                bb.fatal(f"do_updiff: {rel} is back to its state before "
                         f"{os.path.basename(chain[-1][0]['path'])}: that "
                         "patch would become empty. Remove its section by "
                         "hand (and the patch from its .inc if it was the only "
                         "one). Nothing was written.")

            a = os.path.join(tmpdir, 'a')
            b = os.path.join(tmpdir, 'b')
            for path, content in ((a, base), (b, final)):
                if content is None:
                    if os.path.exists(path):
                        os.remove(path)
                else:
                    with open(path, 'wb') as f:
                        f.write(content)
            r = subprocess.run(['diff', '-uN', '--label', f'a/{rel}',
                                '--label', f'b/{rel}', a, b],
                               capture_output=True, text=True,
                               errors='surrogateescape')
            if r.stdout.startswith('Binary files '):
                bb.warn(f"do_updiff: {rel} is binary, skipped")
                continue

            # Rewritten sections must apply with the patch's own striplevel;
            # do_diffcompose labels are a/<rel> b/<rel>, i.e. -p1.
            entry, n = chain[-1]
            if entry['strip'] != 1:
                bb.warn(f"do_updiff: {rel}: {os.path.basename(entry['path'])} "
                        f"uses striplevel={entry['strip']}, skipped")
                continue
            rewrites.setdefault(entry['path'], (entry, {}))[1][n] = r.stdout
            rewritten.append(rel)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    # Second pass: write.
    for path, (entry, new) in rewrites.items():
        with open(path, 'w', errors='surrogateescape') as f:
            f.write(entry['preamble'])
            for n, (_, _, text) in enumerate(entry['sections']):
                f.write(new.get(n, text))

    if appends:
        os.makedirs(append_dir, exist_ok=True)
        used = [int(p[:4]) for p in os.listdir(append_dir)
                if p.endswith('.patch') and p[:4].isdigit()]
        next_number = max(used, default=0) + 1
        for rel, spath in appends:
            name = f"{next_number:04d}-{os.path.basename(rel)}.patch"
            shutil.copyfile(spath, os.path.join(append_dir, name))
            next_number += 1

        inc_path = ib_inc_for(append_dir)
        header = None
        if os.path.isfile(inc_path):
            lines = []
            with open(inc_path) as f:
                for line in f:
                    if line.startswith('#') or not line.strip():
                        lines.append(line)
                    else:
                        break
            header = ''.join(lines) or None
        with open(inc_path, 'w') as f:
            f.write(generate_src_uri(append_dir, header))

    # The series now yields IB_TARGET's content for every file handled, so
    # move those files' attach-manifest entries to it (see base.bbclass: the
    # dirty-tree guards would otherwise keep flagging what was just captured).
    ib_refresh_attach_manifest(d, kept + rewritten + [rel for rel, _ in appends])

    shutil.rmtree(staging)

    sets = sorted({os.path.relpath(os.path.dirname(path), d.getVar('IB_DIR'))
                   for path in rewrites})
    bb.plain(f"do_updiff: {len(kept)} unchanged, {len(rewritten)} rewritten, "
             f"{len(appends)} appended"
             + (f" (into {os.path.relpath(append_dir, d.getVar('IB_DIR'))})"
                if appends else "")
             + (f"; patchsets touched: {', '.join(sets)}" if sets else ""))
}

addtask do_diffcompose before do_updiff


EXPORT_FUNCTIONS do_patch do_diffcompose do_updiff
