---
title: Bypass Cached Failure
tags: nix
---

When evaluating a nix expression, sometimes you get a failure. But then, on next evaluation, you get
this error message:

```bash
$ nix build .#checks.x86_64-linux.modules
error: cached failure of attribute 'checks.x86_64-linux.modules'
```

The failure got cached! How do you see the error message again? By adding `--option eval-cache
false`:

```bash
$ nix build .#checks.x86_64-linux.modules --option eval-cache false
...
```
