.. _release_process:

Release process
###############

Infrabase follows a branch-per-release model, the same as SO3: development
happens on ``main``, and every minor version gets a long-lived maintenance
branch on which patch releases are tagged. This keeps stable lines alive for
backports — the product trees built on Infrabase pin a line, not a commit —
while ``main`` moves on.

Overview
********

Three git objects work together, and GitHub surfaces them in different places:

.. list-table::
   :header-rows: 1
   :widths: 22 20 58

   * - Object
     - Example
     - Role
   * - ``main`` branch
     - ``main``
     - Continuous development (the next, unreleased version).
   * - ``release/vX.Y`` branch
     - ``release/v1.0``
     - Long-lived maintenance line for a minor version. Patch fixes land here
       and are tagged.
   * - Tag ``vX.Y.Z``
     - ``v1.0.0``
     - Immutable point marking a delivered version. Release candidates use the
       ``-rc`` suffix (``v1.0.1-rc``).
   * - GitHub Release
     - "Infrabase v1.0.0"
     - The release page (notes + assets), attached to a tag. Exactly one is
       flagged *Latest*; ``-rc`` tags are published as *pre-release*.

Versioning
**********

Versions follow semantic versioning ``vMAJOR.MINOR.PATCH``. What a product tree
relies on is the build interface — the ``IB_*`` configuration variables, the
command line of the scripts, the layer layout and the classes recipes inherit —
so that is what the numbers are about:

* **MAJOR** — breaking changes to that interface: a variable renamed or with a
  new meaning, a script option removed, a class or layer reorganised so that a
  product layer no longer applies.
* **MINOR** — new features, backward compatible (a new platform, boot stage,
  script option). Opens a new ``release/vX.Y`` branch.
* **PATCH** — bug fixes only, cut *on* an existing ``release/vX.Y`` branch.

Release candidates append ``-rc`` (optionally ``-rcN`` for successive
candidates), e.g. ``v1.1.0-rc``.

Which release is running?
*************************

Every script under ``scripts/`` prints the release it belongs to when it
starts, on stderr, once per invocation — also when it runs another one
(``build.sh`` runs bitbake through the ``scripts/bitbake`` wrapper,
``dbuild.sh`` runs a script in the container)::

   [infrabase v1.0.0] deploy.sh bsp-linux

The version comes from ``scripts/ibversion.sh``, which reads the git release
tag (``git describe``) and keeps only the base version: a tagged commit and
development on top of ``v1.0.0`` both report ``1.0.0``, while ``-rc`` is kept.
A tree without git metadata falls back to the ``IB_VERSION_FALLBACK`` constant
of that script. ``ibversion.sh`` can also be run on its own.

Branch layout
*************

::

   main ──●──●──●──●──●──●───────►   development (next version)
           \
   release/v1.0  ●──●──●             maintenance line for 1.0.x
                 │  │  └─ v1.0.1     (tags live on the branch)
                 │  └──── v1.0.1-rc
                 └─────── v1.0.0

While a minor line has not diverged from ``main`` yet (no work started on the
next minor), its ``release/vX.Y`` branch and ``main`` may point at the same
commit — that is expected.

Which fixes go on a release branch?
***********************************

Being a bug fix is *not* what sends a change to a release branch. ``main`` is
the continuous development line and carries both features **and** fixes as they
land; anything committed there simply ships in the next version. There are two
kinds of fix:

* **A fix for unreleased code, or one that can wait for the next version.**
  Nothing special — it is an ordinary commit on ``main`` and ships in the next
  ``vX.Y.0``. Do *not* touch any release branch.
* **A fix for an already-published version** (e.g. a bug in ``v1.0.0``) that
  must ship *before* the next version. Only this case uses the patch-release
  procedure below: the fix lands on ``release/v1.0`` (tagged ``v1.0.1``) and is
  also carried to ``main`` so it is not lost at the next minor.

In other words, what sends a change to ``release/vX.Y`` is the need to patch a
*live, already-released* version — never the mere fact that it is a fix rather
than a feature. A documentation-only change does not justify a patch release
either: it rides the next version.

Cutting a patch release (``vX.Y.Z``)
************************************

Patch fixes are committed **on the release branch**, then tagged. If a fix was
first merged into ``main``, cherry-pick it onto the branch rather than
fast-forwarding. Do it as a pull request whose base is the release branch, so
the workflows run on the exact tree the tag will point at.

.. code-block:: sh

   git checkout release/v1.0
   git cherry-pick <sha>          # or commit the fix directly
   # bump IB_VERSION_FALLBACK in scripts/ibversion.sh to 1.0.1

   # optional: publish a candidate first
   git tag -a v1.0.1-rc -m "infrabase v1.0.1-rc"
   git push origin release/v1.0 v1.0.1-rc
   gh release create v1.0.1-rc --title "Infrabase v1.0.1-rc" \
       --target release/v1.0 --prerelease --generate-notes

   # final release
   git tag -a v1.0.1 -m "infrabase v1.0.1"
   git push origin release/v1.0 v1.0.1
   gh release create v1.0.1 --title "Infrabase v1.0.1" \
       --target release/v1.0 --latest --notes-file <notes>

Cutting a new minor release (``vX.Y.0``)
****************************************

When ``main`` is ready for a new minor version, prepare it on ``main`` first (a
pull request carrying the ``CHANGELOG`` entry, the *Maintained versions* table
and ``IB_VERSION_FALLBACK`` set to the version being cut), then branch off and
tag:

.. code-block:: sh

   git checkout main
   git checkout -b release/v1.1
   git push -u origin release/v1.1

   git tag -a v1.1.0 -m "infrabase v1.1.0"
   git push origin v1.1.0
   gh release create v1.1.0 --title "Infrabase v1.1.0" \
       --target release/v1.1 --latest --notes-file <notes>

The release notes are the version's ``CHANGELOG`` entry.

After tagging: propagate the release to ``main``
************************************************

A release is not finished when the tag is pushed. The references to the current
version that live on ``main`` must be bumped right after every release (they
drift silently otherwise):

* the *Maintained versions* table in ``README.md`` (the *Latest release*
  column of the line, and the *Status* column when a new minor line starts);
* a ``CHANGELOG`` entry summarizing the release (same content as the GitHub
  Release notes, kept in the repository for offline reference);
* ``IB_VERSION_FALLBACK`` in ``scripts/ibversion.sh``, used only when the tree
  carries no git metadata (a tarball export, a copy without ``.git``).

Two version strings need **no** action: the scripts' release banner and the
documentation version both derive from the release tag
(``scripts/ibversion.sh``, reused by ``doc/source/conf.py``).

Before tagging: check the tree
******************************

The ``Docs`` workflow runs on every branch, ``release/**`` included, and must be
green on the commit the tag will point at::

   gh run list --workflow Docs --branch release/v1.0

Infrabase has no build workflow of its own — a full build needs a kernel, a
rootfs and a privileged container for the deploy — so the build itself is
checked by hand, in the build container, on the commit being tagged: at least
``virt64`` with ``build.sh bsp-linux``, ``deploy.sh bsp-linux`` and a boot to the
login prompt with ``st.sh``. The product trees that consume a release (SO3,
the course trees, EDGE-M1, MICOFE) build it again in their own CI.

Check ``IB_VERSION_FALLBACK`` too: it must already read the version being
tagged, since the tagged tree is what a gitless copy reports. It appears twice
in this page on purpose — bump it **in the release commit set** so the tag is
right, and again when propagating to ``main`` so the next release does not start
a version behind.

Rules of thumb
**************

* One ``release/vX.Y`` branch **per minor**, not per patch — patches are tags
  *on* the branch.
* Tags are immutable: never move or delete a published ``vX.Y.Z`` tag. To
  correct a release, cut the next patch.
* Exactly one GitHub Release carries the *Latest* flag; every ``-rc`` Release is
  a *pre-release* so it never shadows the latest stable version.
* Once a ``release/vX.Y`` branch has diverged from ``main``, backport fixes with
  ``git cherry-pick`` — do not fast-forward the branch onto ``main``.
