---
title: Nix Log a Flake Output
tags: nix
---

After running a `nix build` command and getting an error, the output usually prompts you to run nix log like so:

> `For full logs, run 'nix log /nix/store/iyp0l0h9ik0zkmmg8ryxmb8y15a32apz-self-host-blocks-manual.drv'`

This is great but a bit heavy on copy/pasting. Also, if you update your code and build again, the hash will change as expected but that requires you to copy/paste again, you can't use your terminal's history to quickly check the logs.

One solution is to add `-L` (`--print-build-log`) [cli argument][1] to the `nix build` command. I
use it when the output stays small but for long running output I find it just clutters the terminal
output.

[1]: https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-build#opt-print-build-logs

I just found out that you can use `nix log` on the same flake output you use in `nix build` and get to see the logs too! An example:

```nix
nix build .#manualHtml
nix log .#manualHtml
```

No copy/pasting involved!
