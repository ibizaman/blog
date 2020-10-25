---
title: Deploy the Blog to GitHub Pages
tags: hakyll, haskell, nix
---

I want to use GitHub Pages because it is a very simple to use static
site server and it is readily available when using GitHub. We could
try to use GitHub CI to deploy to GitHub Pages but I do not want to
deal with this complexity just yet.

The method I will use for now is manual and requires two repositories:
one that holds the source code and the other that holds the generated
static files. The easiest way to handle this is to use a git
submodule. (I say easiest but I still spent a few hours setting this
up correctly...)

In my case, the repository holding the static files is
[https://github.com/ibizaman/ibizaman.github.io](https://github.com/ibizaman/ibizaman.github.io)
and the one holding the source code is
[https://github.com/ibizaman/blog](https://github.com/ibizaman/blog).
In the latter, we will create a submodule pointing to the former. In
other words, the submodule will be in the repository holding the
source code.

# Setup a Deploy Command

In essence, we need to build the site and copy the resulting files to
the submodule's path. We then commit and push the submodule to its
repository.

I tried first to simply use the `_site/` directory, output of the
`./result/bin/site build` command, as the submodule. The issue is the
`./result/bin/site rebuild` command completely wipes the `_site/`,
including the submodule's `.git` directory. This puts the submodule in
a bad state.

Next solution is to generate the files in `_site/` then copy them to
the submodule's directory. Usually, that's where I start putting
commands in a `Makefile` so I don't forget how to handle this. But
actually, Hakyll allows you to run a custom command when running
`./result/bin/site deploy`. This is configured in `site.hs`. We will
use that as a self-contained Makefile. Documentation can be found on
[Hackage](https://jaspervdj.be/hakyll/reference/Hakyll-Core-Configuration.html#t:Configuration).

In `site.hs`, we change:

``` diff
+conf :: Configuration
+conf = defaultConfiguration {
+    deployCommand = "rm -rf ibizaman.github.io/* && cp -r _site/* ibizaman.github.io"
+  }

 main :: IO ()
-main = hakyll $ do
+main = hakyllWith conf $ do
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

You often don't need to do the first two steps as `./result/bin/watch`
takes care of it.

I'm sure I will get annoyed of running these commands at some point in
the future but it's good enough for now.
