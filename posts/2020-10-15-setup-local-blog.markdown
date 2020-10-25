---
title: Setup a Hakyll Blog with Nix
tags: hakyll, haskell, nix
---

This blog post explains how to setup this site. You can find the
source code on [GitHub](https://github.com/ibizaman/blog). We will not
publish yet, it will be all local. Publishing is for the following
post.

The stack we'll be using is [Hakyll](https://jaspervdj.be/hakyll/) on
top of [Haskell](https://www.haskell.org/) and
[Nix](https://nixos.org/). I use
[Emacs](https://www.gnu.org/software/emacs/) as my editor so there
will be some later blog posts explaining how to set that up.

We will start by writing Nix files and for learning Nix, I recommend
the [Nix pills](https://nixos.org/guides/nix-pills/index.html). I
thought I could simply find example snippets online and learn from
that but the language and the conventions were too alien for me to
understand anything.

I followed [this blog
post](https://robertwpearce.com/hakyll-pt-6-pure-builds-with-nix.html)
from Robert Pearce to set things up. I removed the `niv` part as I am
not using it.

There was an encoding bug as I'm using UTF-8 but by default Hakyll
only understands ASCII encoding. To solve that one, I followed [this
blog
post](https://www.slamecka.cz/posts/2020-06-08-encoding-issues-with-nix-hakyll/)
from Ondřej Slámečka. There is a fix in the [Hakyll's
FAQ](https://jaspervdj.be/hakyll/tutorials/faq.html#hgetcontents-invalid-argument-or-commitbuffer-invalid-argument),
but the post from Ondřej is tailored for nix so I followed it.

I recommend reading both blog posts as they explain things well. That
said, here is my version.

# Initial Nix Files

Corresponds to [this commit](https://github.com/ibizaman/blog/commit/b4200e564d8464f6783a38a14e8be059ef28b425).

There are 3 nix files to create, then we will be able to use
`hakyll-init` to generate the base site.

## `./default.nix`

``` nix
(import ./release.nix { }).project
```

## `./shell.nix`

``` nix
(import ./release.nix { }).shell
```

## `./release.nix`

``` nix
# https://robertwpearce.com/hakyll-pt-6-pure-builds-with-nix.html
{ compiler ? "ghc883"
, pkgs ? import <nixpkgs> {}
}:

let
  inherit (pkgs.lib.trivial) flip pipe;
  inherit (pkgs.haskell.lib) appendConfigureFlags;

  haskellPackages = pkgs.haskell.packages.${compiler}.override {
    overrides = hpNew: hpOld: {
      hakyll =
        pipe
           hpOld.hakyll
           [ (flip appendConfigureFlags [ "-f" "watchServer" "-f" "previewServer" ])
           ];

      # https://www.slamecka.cz/posts/2020-06-08-encoding-issues-with-nix-hakyll/
      hakyll-blog = (hpNew.callCabal2nix "blog" ./. { }).overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs or [] ++ [
          pkgs.makeWrapper
        ];
        postInstall = old.postInstall or "" + ''
        wrapProgram $out/bin/site \
          --set LANG "en_US.UTF-8" \
          --set LOCALE_ARCHIVE "${pkgs.glibcLocales}/lib/locale/locale-archive"
        '';
      });
    };
  };

  project = haskellPackages.hakyll-blog;
in
{
  project = project;

  shell = haskellPackages.shellFor {
    packages = p: with p; [
      project
    ];
    buildInputs = with haskellPackages; [
      ghcid
      ghcide
      brittany
      hlint
    ];
    withHoogle = true;
  };
}
```

The first two files are using the `release.nix` one so let's dive into
that one.

First, we set some defaults and import some functions:

``` nix
{ compiler ? "ghc883"
, pkgs ? import <nixpkgs> {}
}:

let
  inherit (pkgs.lib.trivial) flip pipe;
  inherit (pkgs.haskell.lib) appendConfigureFlags;
```

Then we set some overrides. To know what an override is, check the
[Nix pills](https://nixos.org/guides/nix-pills/override-design-pattern.html).

``` nix
haskellPackages = pkgs.haskell.packages.${compiler}.override {
  overrides = hpNew: hpOld: {
```

First for Hakyll, we configure it with `watchServer` and
`previewServer` options. Both options are super useful when developing
as the produced `./result/bin/site` executable will watch for file
changes and rebuild the blog post when needed.

``` nix
hakyll =
  pipe
     hpOld.hakyll
     [ (flip appendConfigureFlags [ "-f" "watchServer" "-f" "previewServer" ])
     ];
```

Second, we create a variable `hakyll-blog` to compile the blog. The
name `"blog"` must correspond to the name of the cabal file, which we
will generate later. We also set some flags to make Hakyll able to
read UTF-8 files.

``` nix
hakyll-blog = (hpNew.callCabal2nix "blog" ./. { }).overrideAttrs (old: {
  nativeBuildInputs = old.nativeBuildInputs or [] ++ [
    pkgs.makeWrapper
  ];
  postInstall = old.postInstall or "" + ''
  wrapProgram $out/bin/site \
    --set LANG "en_US.UTF-8" \
    --set LOCALE_ARCHIVE "${pkgs.glibcLocales}/lib/locale/locale-archive"
  '';
});
```

We then set the `project` variable used in the `default.nix` file:

``` nix
  project = haskellPackages.hakyll-blog;
in
{
  project = project;
```

Finally, we set the `shell` variable and provide some packages useful
for editors, namely `ghcide`, `brittany`, `hlint` and a local `hoogle`
with `withHoogle`:

``` nix
shell = haskellPackages.shellFor {
  packages = p: with p; [
    project
  ];
  buildInputs = with haskellPackages; [
    ghcid
    ghcide
    brittany
    hlint
  ];
  withHoogle = true;
};
```

# Generate the Initial Template Blog

Corresponds to [this commit](https://github.com/ibizaman/blog/commit/990cea6051a978ca407ff2ed3921d7deb3652e5c).

Next step will take some time because we will run Nix for the first
time. It will fetch and compile every dependencies. It took roughly 1
hour on my laptop.

``` bash
$ nix-shell --pure -p haskellPackages.hakyll --run "hakyll-init ."
```

This will generate a cabal file named after the git repo's directory. Here is an example, with the following directory structure:
```
./blog
./blog/.git
```

Running the `hakyll-init .` command in the `blog` directory will create the following files:

``` bash
[nix-shell:~/blog]$ hakyll-init .
Creating ./posts/2015-11-28-carpe-diem.markdown
Creating ./posts/2015-10-07-rosa-rosa-rosam.markdown
Creating ./posts/2015-12-07-tu-quoque.markdown
Creating ./posts/2015-08-12-spqr.markdown
Creating ./site.hs
Creating ./images/haskell-logo.png
Creating ./templates/post-list.html
Creating ./templates/default.html
Creating ./templates/archive.html
Creating ./templates/post.html
Creating ./css/default.css
Creating ./index.html
Creating ./about.rst
Creating ./contact.markdown
Creating ./blog.cabal
```

You get a bunch of files and 4 example blog posts under the `posts/`
directory. Also, the Cabal file `blog.cabal` is named from the
directory and must be named that way for the `release.nix` file to
work correctly, as we established previously.

Then, we can build the `./result/bin/site` blog executable:

``` bash
$ nix-build --show-trace
```

Finally, we can run the executable to compile the site, including all
4 example blog posts:

``` bash
./result/bin/site build
```

This will create the `_cache` and `_site` directories. The latter is
where the generated files will be located.

# Serve and Watch For Changes

``` bash
./result/bin/site watch
```

Your blog will be up and running at [http://localhost:8000](http://localhost:8000).

You can change posts, add or remove posts, change the css and other
files and the `site` executable will see those changes and rebuild the
site. You just need to reload the site in your browser.

# Gitignore

Corresponds to [this commit](https://github.com/ibizaman/blog/commit/731642ddf603bf348a50450055558ca3b57e469d).

I can't live with temporary and generated files like that. Let's add a
`.gitignore`:

```
*#
*~
_cache/
_site/
result
```

The first two lines are for Emacs' temporary files, you could omit
them.

# Your First Post

I just deleted all 4 example blog posts and [created another
file](https://github.com/ibizaman/blog/commit/b8f97be67e44bb811524d7235414f8d8899281d5).

# Conclusion

That's it, we created our blog with Hakyll and Nix and we can see it
locally. Next up, let's publish it.
