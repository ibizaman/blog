---
title: Flakify This Blog
tags: nix, blog
---

# Motivation

I wanted to use flakes to build this blog since quite a while but never got to it.

The last nudge needed was I was fed up with the current deploy process which involved a [second
repository](https://github.com/ibizaman/ibizaman.github.io) (see a [previous blog post][1] for more
details). It was really hindering my motivation to write blog posts. I wanted instead to deploy by
just pushing to the main branch thanks to a GitHub action, like any sane person.

[1]: 2020-10-16-1-deploy-to-github-pages.html#actually-deploy

# First Try

In one of my other projects, that's exactly what I did thanks to a [GitHub action][2], so I copied
that action and just updated the part on how to build the docs.

[2]: https://github.com/ibizaman/selfhostblocks/blob/main/.github/workflows/pages.yml

```yaml
name: Deploy blog

on:
  # Runs on pushes targeting the default branch
  push:
    branches: ["main"]

  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

# Sets permissions of the GITHUB_TOKEN to allow deployment to GitHub Pages
permissions:
  contents: read
  pages: write
  id-token: write

# Allow only one concurrent deployment, skipping runs queued between the run in-progress and latest queued.
# However, do NOT cancel in-progress runs as we want to allow these production deployments to complete.
concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  # Single deploy job since we're just deploying
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Install nix
        uses: cachix/install-nix-action@v20

      - name: Build docs
        run: |
          nix-build -v

          ./result/bin/site build

          mkdir -p ibizaman.github.io
          ./result/bin/site deploy

          # see https://github.com/actions/deploy-pages/issues/58
          cp \
            --recursive \
            --dereference \
            --no-preserve=mode,ownership \
            ibizaman.github.io \
            public

      - name: Setup Pages
        uses: actions/configure-pages@v3

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v1
        with:
          path: ./public

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v2
```

But `nix-build` failed with:

> ```
> file 'nixpkgs' was not found in the Nix search path
> (add it using $NIX_PATH or -I)
> ```

This is because the `release.nix` file uses the bracket syntax `<nixpkgs>` [to find nixpkgs][3] in
the `$NIX_PATH`.

[3]: https://github.com/ibizaman/blog/blob/4f3e3337ba82a7606fe2f5fefbc0b19ad4c4748e/release.nix#L3

Now, `cachix/install-nix-action` does [have a way][4] to add `nixpkgs` to the nix path, so I
could've done that. Instead, I took the time to switch to flakes to avoid needing to change the
`$NIX_PATH` at all.

[4]: https://github.com/cachix/install-nix-action#usage

# Use Flakes to Build Hakyll

Now, I tried a few variations of a `flake.nix` file. First, copying the `release.nix` and just
adding an `inputs` section. Then, I tried [the template][5] from `haskell.nix` using `haskell.nix`.
In both cases, I was recompiling a lot of Haskell packages.

[5]: https://github.com/input-output-hk/haskell.nix/blob/master/docs/tutorials/getting-started-flakes.md

Finally, I found [hakyll-flakes](https://github.com/Radvendii/hakyll-flakes). My `flake.nix` file is now:

```nix
{
  description = "ibizaman's blog";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    hakyll-flakes.url = "github:Radvendii/hakyll-flakes";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, hakyll-flakes, flake-utils, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
      flake-utils.lib.eachSystem supportedSystems (system:
        hakyll-flakes.lib.mkAllOutputs {
          inherit system;
          name = "site";
          src = ./.;
          websiteBuildInputs = with nixpkgs.legacyPackages.${system}; [
            # rubber
            # texlive.combined.scheme-full
            # poppler_utils
          ];
        });
}
```

Building the project is done with `nix build .#website` which generates the html files under
`result/` folder:

```
$ ls -1 result
about.html
archive.html
atom.xml
contact.html
css
images
index.html
posts
tags
tags.html
```

Also, `nix run . watch` is very useful.

# Deploy with GitHub Action

I just needed to update the GitHub action:

```yaml
- name: Build docs
  run: |
    nix \
      --print-build-logs \
      --show-trace #\
      build .#website

    # see https://github.com/actions/deploy-pages/issues/58
    cp \
      --recursive \
      --dereference \
      --no-preserve=mode,ownership \
      result \
      public
```

Finally, I needed to configure the Settings > Environments > Configure github-pages to allow
deploying from my `main` branch.

The two relevant commits are [6969b9][10] and [4f3e33][11].

[10]: https://github.com/ibizaman/blog/commit/6969b9986aeacccb6fa1bd6fac372ffec3f53c37
[11]: https://github.com/ibizaman/blog/commit/4f3e3337ba82a7606fe2f5fefbc0b19ad4c4748e

The only thing to remember now is to correctly commit the blog post, which I already managed to forget once :D

# Addendum

I needed to disable the pages integration on my second - now useless - repo so that I could add the correct custom domain to deploy to to my current repo. I just went and archive that second repo altogether.
