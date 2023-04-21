---
title: Sops on NixOps 2
tags: nix, server
---

Setting Sops is done by following the steps in the [README](https://github.com/Mic92/sops-nix#usage-example) file. But I struggled on "Get a public key for your target machine" one. This is what it tells us to do:

```bash
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```

But you need to ssh into the machine to get the public key. How to do that? Well, this "little" one liner does the trick:

```bash
nixops export --network dev | jq '..|."virtualbox.publicHostKey"? | select(. != null)' -r
```

- The `..` is a recursive descent on all JSON object fields.
- We're searching for the field names `virtualbox.publicHostKey`. We
  need the double quotes because the dot is actually part of the field
  name.
- We then select the non null items, effectively keeping the only match.

This outputs something like `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhZqrj2+idV2uZXHUp2Q4sJ8SzRWGYz0nHSKuiW5oo3 NixOps auto-generated key`.

You can then pipe that to `ssh-to-age` and go to the next step.
