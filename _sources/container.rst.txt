.. _container:

Containerised build environment
###############################

The build environment is available as a container image, driven by the
``dbuild.sh`` :term:`standard script`. It is the recommended way to build: the
image carries the cross toolchains, the host packages and Python, so nothing has
to be installed on your machine, and every developer builds against the same,
pinned environment.

The image contains **no project source**. The repository stays on the host and is
bind-mounted at its *own absolute path*, which is what makes the container and
the host interchangeable — BitBake stamps, the buildroot host tree, CMake caches
and the ``*.attach.sha256`` manifests all embed absolute paths, so a tree built
inside the container can be built further outside it, and the other way round.

Usage
*****

.. code-block:: text

   dbuild.sh --build              Build (or rebuild) the image
   dbuild.sh                      Interactive shell inside the container
   dbuild.sh build.sh bsp-linux   Run a build
   dbuild.sh deploy.sh bsp-linux  Deploy it
   dbuild.sh -h                   Print help

.. code-block:: bash

   $ scripts/dbuild.sh --build               # once, or after changing the image
   $ scripts/dbuild.sh build.sh bsp-linux
   $ scripts/dbuild.sh deploy.sh bsp-linux

Any command is run with ``env.sh`` already sourced and with the current directory
preserved, so ``dbuild.sh`` in front of a command you already know is all there is
to it. With no command you get an interactive shell instead, with the environment
sourced and a ``[ib-build]`` prompt to make it obvious where you are — the tree
looks identical to the host one, same absolute paths.

Two environment variables adjust the invocation:

+---------------------+-----------------------------------------------------+
| Variable            | Meaning                                             |
+=====================+=====================================================+
| ``IB_DOCKER_IMAGE`` | Image name:tag, default ``infrabase-build:1.0``.    |
+---------------------+-----------------------------------------------------+
| ``IB_DOCKER_OPTS``  | Extra options passed to ``docker run``.             |
+---------------------+-----------------------------------------------------+

Running as you, not as root
***************************

Everything the recipes write lands in the bind-mounted repository — attached
source trees, ``build/tmp``, the storage images. If the container ran as root,
all of it would come back root-owned on the host, reintroducing exactly the
ownership churn the unprivileged-bitbake model removes.

The UID/GID cannot be baked into the image (they differ per host), so
``dbuild.sh`` passes ``HOST_UID``/``HOST_GID`` and the image's entrypoint starts
as root, materialises a matching account, then drops to it with ``setpriv`` —
no extra process in the signal path, so Ctrl-C reaches the build and exit codes
propagate.

Inside a throw-away container, the privileged build steps take the simple route:
a blanket ``NOPASSWD`` sudoers rule, plus ``Defaults !authenticate`` because the
scripts open their session with ``sudo -v``, which validates the *user* rather
than a command. This also means the container is the answer when the host's own
``sudo`` gets in the way.

What the container is given
***************************

* ``--privileged`` and ``/dev`` — the storage steps need loop devices, ``mount``
  and ``mkfs``. Loop devices are a **host-kernel** resource, so concurrent builds
  on one machine contend for them exactly as they do outside a container.
* ``--network host`` — keeps ``st.sh``'s slirp port forwards and the GDB stub
  reachable from the host without publishing ports, and lets the recipes fetch
  through the host resolver.
* The ssh-agent socket, when present, so a fetch over SSH works from inside.
  Nothing is copied into the image.
* ``DISPLAY`` and the X11 socket *with the X cookie* — what ``st.sh -d`` needs
  to open its window — mounted at its own path
  with ``XAUTHORITY`` pointing at it — the container user has a different
  ``HOME``, and under Wayland the cookie lives outside ``HOME`` anyway.
* stdin, always (``-i``): without it Docker hands the container ``/dev/null`` and
  piping into a containerised command would silently deliver nothing. A tty
  (``-t``) is allocated only for a real terminal, so CI logs stay clean.

Caveats
*******

* **A mount lives only as long as the container that made it.** ``dbuild.sh
  mount.sh`` mounts inside its own mount namespace, and the mount is gone once
  the command returns. Run the mount and whatever uses it in the *same*
  container — typically from an interactive ``dbuild.sh`` shell.
* **A server started inside dies with the command.** The container runs with
  ``--rm``, so ``dbuild.sh`` starts the TEZI feed server on the *host* after the
  container exits instead (it shares the host network namespace, but not its
  lifetime).
* **A snap-packaged Docker can only bind-mount paths under ``$HOME``**: the
  confined daemon fails with "read-only file system" elsewhere. This only matters
  for a ``site.conf`` that points ``IB_HTTP_DEPLOY_PATH`` outside the tree — the
  default feed is inside the bind-mounted tree. ``dbuild.sh`` detects the snap
  both by client path and by asking the daemon, and skips such a mount with a
  one-line warning rather than failing every invocation; prefer Docker from the
  apt repository.

The image
*********

The image is defined in ``docker/build-env/``, and the build context is that
directory only — never the project root, which holds tens of gigabytes of build
output.

+--------------------+---------------------------------------------------------+
| File               | Role                                                    |
+====================+=========================================================+
| ``Dockerfile``     | Two stages: fetch the Arm cross toolchain, then build   |
|                    | the environment proper.                                 |
+--------------------+---------------------------------------------------------+
| ``packages.txt``   | **The** host package list, one per line with comments;  |
|                    | also what you install when building on the host.        |
+--------------------+---------------------------------------------------------+
| ``entrypoint.sh``  | Materialises the host user and drops to it.             |
+--------------------+---------------------------------------------------------+
| ``bashrc``         | rc file for the interactive shell (sources ``env.sh``). |
+--------------------+---------------------------------------------------------+

The toolchain version is pinned in the ``Dockerfile``
(``aarch64-none-linux-gnu`` 12.3.rel1): bump it there, rebuild the image and
re-validate — never by installing something else on a host. Adding a host
dependency means adding a line to ``packages.txt``; the Dockerfile installs that
file verbatim.

.. note::

   Sourcing ``env.sh`` happens in the interactive shell's rc file rather than in
   a parent process on purpose: ``env.sh`` defines shell *functions* (the
   ``cd``/``pushd``/``popd`` wrappers and ``ib_autoswitch_*``), which only exist
   in the shell that sourced them. A parent that sources it and then execs bash
   passes on the exported variables but loses the functions.
