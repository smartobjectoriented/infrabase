
.. _dev_flow:

Development  flow
#################

Here is an overview of the *development flow* used in the Infrabase project.

*  **Current**/**latest** version of the framework is available in the ``main``
   branch.
*  The development activities are done in a specific branch. An issue is linked
   with each development branches.
*  Once the development of a new feature has completed, the developer opens a ``pull
   request (PR)``. The *changes* are reviewed and then merged into the ``main`` branch
   by the *Infrabase maintainers*.

The gitFlow_ figures shows this flow.

Periodically, the *maintainers* publish a major release of the *Infrabase*.
For a new version, the following steps are performed:

*  The main new features has been re-tested
*  The ``CHANGELOG`` file is updated with the new release information (release
   number, description of the main add-on to the framework, ...)
*  A ``tag`` with the version number is created

.. _gitFlow:
.. uml::

   master->>FeatureA: Create branch
   master->>FeatureB: Create branch
   FeatureA->>master: Merge new feature in master
   FeatureB->>master: Merge new feature in master


Development
***********

For the development of new features or improvements, a new branch has to be created.
It should not be any development done directly in the ``main`` branch. Each new
*topic* has to have is own branch. Branches are not reused.

An issue should be linked with each branch (an issue per branch). This issue should
provide:

*  A description of what is addressed
*  (Optional) Information on the advancement of this topic, issues
   found, explanation of the implementation, …

The issue is automatically closed after
the development branch is merged of in the ``main`` branch.

.. note::

   Issue can be (should be) created to document problems, improvement found using
   the framework without having to create a branch.

   The branch can be created when the *issue* is addressed

Create new issue & branch
=========================

Infrabase is hosted on `GitHub <https://github.com/smartobjectoriented/infrabase>`__. To create a
branch with an associated issue:

1. Create a new issue: `Creating an issue
   <https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue>`__
2. Create the branch from the issue, so the two stay linked: `Creating a branch to work on
   an issue <https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-a-branch-for-an-issue>`__


Merge in the main branch
========================

Once the development of a specific topic has completed and been tested, it has to be
*integrated* in the ``main`` branch. It is done by opening a ``pull request (PR)``.

By opening a ``pull request``, a developer asks the *Infrabase maintainers* to:

-  Do a review of the modifications
-  Perform the ``merge``

Either from the branch page on GitHub, or with the CLI:

.. code-block:: bash

   $ gh pr create --base main

`Pull request official doc
<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request>`__.

A PR description should say **what** changed and **why**, and how it was tested — which
platform, which recipes, and whether the result was actually run.

.. note::
	
	Ideally, there is only one commit per changes. If, for some reasons, it is not 
	possible, please inform the *dev team* to lock this branch. 
