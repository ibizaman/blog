---
title: Bisect Experiment at the PR Level
tags: nix, forge action, auto update
---

<!--toc:start-->
- [First Automation Attempt](#first-automation-attempt)
- [Naive Commit Selection](#naive-commit-selection)
- [Smarter Commit Selection](#smarter-commit-selection)
- [Manual Run](#manual-run)
- [Links](#links)
- [Possible Improvement](#possible-improvement)
- [Upstreaming](#upstreaming)
<!--toc:end-->

I maintain the [SelfHostBlocks][] project.
It relies on `nixos/nixpkgs/unstable` as its sole dependency
and it attempts to follow the latest commit as close as possible.

If you're wondering why, it's because I like the shiny new stuff.

# First Automation Attempt

To automate this update process,
I initially created a crude workflow which worked like follows:

1. Workflow runs at midnight.
   It runs `nix flake update nixpkgs`
   and if this results in a change in the `flake.lock` file,
   it commits that and creates a PR with the `automerge` label.
   If a PR already exists, it instead force pushes to that PR.
2. When the PR is created with the `automerge` label,
   the auto-merge feature of Github gets activated.
3. Custom NixOS VM tests run on this PR and if they all succeed,
   the `flake.lock` update PR gets merged automatically.

I wrote more extensively about this in [another blog post][].

[SelfHostBlocks]: https://github.com/ibizaman/selfhostblocks
[another blog post]: https://blog.tiserbox.com/posts/2023-12-25-automated-flake-lock-update-pull-requests-and-merging.html

# Naive Commit Selection

Although this is automated and did produce PRs that get auto-merged,
more often than not the commit selection is too naive.
Constantly trying to update to the tip of unstable can lead to test failure.

The most frequent reasons for failure are:

1. A package I rely on cannot be built.
2. A module option got updated leading to some breaking change.
3. The behavior of a module changed and broke an assumption I had.

The workflow being naive does not realize the PR it had created has a failure
and it will happily update the `flake.lock` file to the latest unstable commit.
That might fix the failure when a package cannot be built
but will never fix the other two.

So when that happens, this update PR will be failing until I take a look at it
which is annoying.

# Smarter Commit Selection

I changed the workflow to check if the PR already existed
and if so to check its test status.

If the tests are failing,
it will then clone the nixpkgs repo
and choose the commit in the middle between the last good commit 
(the tip of my project's main branch)
and the latest failing commit
(the PR's nixpkgs commit).

It then uses this new middle commit to run a flake update
similarly as before and pushes that change to the existing PR.

```bash
nix flake update nixpkgs \
  --override-input \
    nixpkgs \
    github:nixos/nixpkgs/$commit
```

If the PR still fails, on next run it will choose again a commit in the middle between the
last good commit and the last failing one.

If the PR succeeds, then it gets auto-merged and the cycle repeats.
The workflow will see no PR is opened so it will update the `flake.lock` file
using the latest commit on `unstable`.

If the tests in the PR continuously fail,
there might be no more commit to bisect on as the good commit will become the parent of bad commit.
In that case, the workflow will go back to the latest commit on `unstable` and will try anew.

# Manual Run

I'm running the workflow every 3 hours
but it is possible to run the workflow manually to speed up the process.
This will be useful when I'm catering it and trying to fix the issues that appear.

When running the workflow manually, I also added an option to bisect a commit _in the future_.
That is to choose a commit between the currently failing one in the PR and the tip of nixpkgs unstable.

# Links

- [Github workflow](https://github.com/ibizaman/selfhostblocks/actions/runs/25743636941/workflow)
- The [nix/bash script used in the workflow](https://github.com/ibizaman/selfhostblocks/blob/main/.github/workflows/update-flake-lock-pr.nix)
- [Example run](https://github.com/ibizaman/selfhostblocks/actions/runs/25743636941/job/75600738546)
- ... which produced [this PR](https://github.com/ibizaman/selfhostblocks/pull/708)
- Another PR [with some failures](https://github.com/ibizaman/selfhostblocks/pull/702)

# Possible Improvement

Always choosing a commit in the past is not necessarily the best strategy.
It could be worth parsing the log output and figuring out what failed.
Indeed, when a package fails to build, choosing a commit in the future might work too
as a broken package is usually fixed in the next couple of days at most.

Choosing a commit in the future is possible thanks to the manual run mode
but this could be made automatic.

Better selection of commits could be helped by using one of the tools in the [wiki][].
`Hydrasect` is particularly interesting to be able to pick a commit with cached derivations.

[wiki]: https://wiki.nixos.org/wiki/Bisecting

# Upstreaming

I'm not even sure this is a good idea and will be useful in practice.
Time will tell.

If others still might like a tool like this,
it could be extracted as its own repo but it should be made generic first.
It should be able to let the user choose which flake input to update.
It is hardcoded to "nixpkgs" now.

I'm also not sure how to best handle updating multiple inputs
as the number of combination of commits to try would explode quickly.
