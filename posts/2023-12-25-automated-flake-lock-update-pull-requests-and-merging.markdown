---
title: Automated Flake Lock Update Pull Requests and Merging
tags: nix, ci
---

This is pretty cool. Thanks to two GitHub workflows, I managed to automate updating the flake.lock
of [my project][9].

[9]: https://github.com/ibizaman/selfhostblocks

Every day at midnight, the first workflow will run, try to update the `flake.lock` file and if
there's an update, it will create a Pull Request with the `automerge` label. The second workflow
runs every time a Pull Request gets updated (opened, labeled, etc.) and enabled auto-merging of the
Pull Request if the `automerge` label is set.

# Create Your Personal Access Token

First thing, you will need to create a Personal Access Token (PAT) to enable both workflow to work.

Go to [your PAT settings][1] and create a Fine Grained PAT. Select which repository the PAT should
be granted for then set `Read and Write` access for both `Contents` and `Pull Requests` permissions.
The resulting PAT should look like this:

[1]: https://github.com/settings/personal-access-tokens

![PAT with `Read and Write` access set for `Contents` (code) and `Pull Requests` permissions.](/images/2023-12-25-automated-flake-lock-update-pull-requests-and-merging/pat.png){.zoom}

The `Contents` permission is needed to create a branch and push commits to it and the `Pull
Requests` one to allow to create a pull request. Both are needed for the first workflow but
admittedly only the latter is needed for the second workflow. You could create a second PAT with
only the `Pull Requests` permission for the second workflow but I didn't go that far.

Now, add the PAT as a repository secret named `GH_TOKEN_FOR_UPDATES` in the secrets page of your
repo, at `https://github.com/<user>/<repo>/settings/secrets/actions`:

![`GH_TOKEN_FOR_UPDATES` repository secret.](/images/2023-12-25-automated-flake-lock-update-pull-requests-and-merging/repo_secrets.png){.zoom}

# Workflow 1: Create PR with Updated `flake.lock`

The workflow uses the [update-nix-flake-lock][2] action from [Determinate Systems][3]:

[2]: https://github.com/marketplace/actions/update-nix-flake-lock
[3]: https://determinate.systems

```yaml
name: Update Flake Lock

on:
  workflow_dispatch:
  schedule:
    - cron: '0 * * * 0' # runs daily at 00:00

jobs:
  lockfile:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3
      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          extra-conf: "system-features = nixos-test benchmark big-parallel kvm"
      - name: Update flake.lock
        uses: DeterminateSystems/update-flake-lock@main
        with:
          token: ${{ secrets.GH_TOKEN_FOR_UPDATES }}
          pr-labels: |
            automerge
```

As stated in the introduction, this workflow runs daily at midnight, calls the
[DeterminateSystems/update-flake-lock][2] action that updates the `flake.lock` file and creates a
Pull Request with the `automerge` label.

Although not necessary, I kept the `workflow_dispatch` trigger as this allows me to run the action
manually. I wasn't going to wait for midnight to test the workflow! :D

By the way, the PAT was necessary to trick GitHub in thinking _I_ created the Pull Request.
Otherwise, GitHub actions are not run if a Pull Request gets created from another action. See [this
section][4] of the README for more details.

[4]: https://github.com/marketplace/actions/update-nix-flake-lock#running-github-actions-ci

# Workflow 2: Auto-Merge PR

You cannot (yet?) enable auto-merging by default in GitHub, so we need instead to enable it
ourselves whenever a Pull Request gets created or updated.

Well, "ourselves" is by using the [auto-merge-pull-request][5] action:

[5]: https://github.com/marketplace/actions/auto-merge-pull-request

```yaml
name: Auto Merge

on:
  # Try enabling auto-merge for a pull request when a draft is marked as “ready for review”, when
  # a required label is applied or when a “do not merge” label is removed, or when a pull request
  # is updated in any way (opened, synchronized, reopened, edited).
  pull_request_target:
    types:
      - opened
      - synchronize
      - reopened
      - edited
      - labeled
      - unlabeled
      - ready_for_review

  # Try enabling auto-merge for the specified pull request or all open pull requests if none is
  # specified.
  workflow_dispatch:
    inputs:
      pull-request:
        description: Pull Request Number
        required: false

jobs:
  automerge:
    runs-on: ubuntu-latest
    steps:
      - uses: reitermarkus/automerge@v2
        with:
          token: ${{ secrets.GH_TOKEN_FOR_UPDATES }}
          merge-method: rebase
          do-not-merge-labels: never-merge
          required-labels: automerge
          pull-request: ${{ github.event.inputs.pull-request }}
          review: ${{ github.event.inputs.review }}
          dry-run: false
```

Again, I left the `workflow_dispatch` trigger for testing, although it wasn't necessary in the end
since I could just toggle the `automerge` label on a Pull Request.

# Result

[This Pull Request][6] was created and merged automatically.

[6]: https://github.com/ibizaman/selfhostblocks/pull/83
