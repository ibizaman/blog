---
title: Add Patches to Nixpkgs
tags: nix
---

_edit 2024-06-15: fix snippet_

Following the trail from [discourse][1] to a [closed GitHub pull request][2] to a comment in a
[second GitHub pull request][3] :) I'm happy to share that we can now easily apply patches to
`nixpkgs` itself.

[1]: https://discourse.nixos.org/t/support-patching-nixpkgs/2737
[2]: https://github.com/NixOS/nixpkgs/pull/59990#issuecomment-1128274552
[3]: https://github.com/NixOS/nixpkgs/pull/142273#issuecomment-948225922

This is pretty neat because now, if you want to apply an open pull request immediately to your
project, you can easily do it. Well, the code is not particularly elegant but it's easier than
cloning [nixpkgs][4] and merging the PR yourself...

[4]: https://github.com/NixOS/nixpkgs

This is what applying a patch looks like now:

```nix
let
  system = "x86_64-linux";
  originPkgs = nixpkgs.legacyPackages.${system};

  patches = [
    (originPkgs.fetchpatch {
      url = "https://patch-diff.githubusercontent.com/raw/NixOS/nixpkgs/pull/315018.patch";
      hash = "sha256-8jcGyO/d+htfv/ZajxXh89S3OiDZAr7/fsWC1JpGczM=";
    })
  ];
  patchedNixpkgs = originPkgs.applyPatches {
    name = "nixpkgs-patched";
    src = nixpkgs;
    inherit patches;
  };
in
  {
    nixpkgs = import patchednixpkgs { inherit system; };
  };
```

On GitHub, to get a patch from a PR, you must go to the PR (for example
[https://github.com/NixOS/nixpkgs/pull/268168](https://github.com/NixOS/nixpkgs/pull/268168)), edit
the URL to add a `.patch` suffix
([https://github.com/NixOS/nixpkgs/pull/268168.patch](https://github.com/NixOS/nixpkgs/pull/268168.path))
and that will redirect you to the final URL (the one in the snippet above for this example).
