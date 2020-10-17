---
title: Deploy the Blog to Github Pages
---

I'm using Github Pages because it is integrated in Github and it is
pretty simple to use. There are ways to use Github CI to deploy to
Github Pages but I will set that up when I feel tired of this manual
method.

The manual method requires two repositories: one that holds the source
code, the other that holds the generated static files. The easiest way
to handle this is to use a git submodule. (I say easiest but I still
spent a few hours setting this up correctly...)

In my case, the repo holding the static files is
https://github.com/ibizaman/ibizaman.github.io and the one holding the
source code is https://github.com/ibizaman/blog. In the latter, we
will create a submodule pointing to the former.

# Setup a Deploy Command

In essence, we need to build the site and copy the resulting files in
the submodule's path. We then commit and push the submodule to its
repo.

I tried first to simply use the `_site/` directory, output of the
Hakyll build, as the submodule. The issue is the `./result/bin/site
rebuild` command completely wipes the `_site/`, including the
submodule's `.git` directory. This puts the submodule in a bad state.

Next solution is to generate the files in `_site/` then copy them to
the submodule's directory. Usually, that's where I start putting
commands in a `Makefile` so I don't forget how to handle this. But
actually, Hakyll allows you to run a custom command when running
`./result/bin/site deploy`. This is configured in `Site.hs`. We will
use that as our self-contained Makefile. Documentation can be found on
[Hackage](https://jaspervdj.be/hakyll/reference/Hakyll-Core-Configuration.html#t:Configuration).

In `Site.hs`, we change:

``` haskell
main :: IO ()
main = hakyll $ do
```

To:

``` haskell
conf :: Configuration
conf = defaultConfiguration { deployCommand = "rm -rf ibizaman.github.io/* && cp -r _site/* ibizaman.github.io" }


main :: IO ()
main = hakyllWith conf $ do
```

This is tailored to the names of my repos, of course. It corresponds
to [this
commit](https://github.com/ibizaman/blog/commit/64d0b697c7863c2b6a9aae5552abb937e66cc6c2).

# Actually Deploy

These are the, arguably manual, steps to deploy this blog:

``` bash
$ nix-build
$ ./result/bin/site rebuild
$ ./result/bin/site deploy
$ (cd ibizaman.github.io && git commit -m 'MESSAGE' && git tag TAG && git push)
$ git commit -m 'MESSAGE' && git push
```

I'm sure I will get annoyed to run these commands at some point but
for now, it's good enough.
