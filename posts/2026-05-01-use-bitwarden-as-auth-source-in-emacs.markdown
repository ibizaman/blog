---
title: Use Bitwarden as auth source in Emacs
tags: nix, emacs
---

<!--toc:start-->
- [1. Setup Emacs](#1-setup-emacs)
- [2. Setup nix config](#2-setup-nix-config)
- [3. Configure secret](#3-configure-secret)
- [Misc](#misc)
  - [Clear auth-sources cache](#clear-auth-sources-cache)
  - [Self-hosted Bitwarden](#self-hosted-bitwarden)
  - [Log into vault](#log-into-vault)
  - [Unlock vault](#unlock-vault)
  - [Sync vault](#sync-vault)
<!--toc:end-->

From Magit, it is possible to create pull requests.
Of course, we need to setup a secret token to be able to create a pull request on the forge.

One way is to store the secret in a file read by emacs.
By default, those files are:

```elisp
("~/.authinfo" "~/.authinfo.gpg" "~/.netrc")
```

The issue is these files store the secrets in clear text.
Instead, let's configure emacs to read the secret from Bitwarden.

## 1. Setup Emacs

We add usage of the [emacs-bitwarden][] package in our `init.el` file:

[emacs-bitwarden]: https://github.com/seanfarley/emacs-bitwarden/

```nix
(use-package bitwarden
  :ensure t
  :config
  (bitwarden-auth-source-enable))
```

The package is only available on github so we'll need to package it ourselves in the next section.

## 2. Setup nix config

I use the [emacs-overlay][] NixOS module to install emacs.
Assuming the following base nix config:

[emacs-overlay]: https://github.com/nix-community/emacs-overlay

```nix
let
  emacsWithPackages = pkgs.emacsWithPackagesFromUsePackage {
    config = emacs-conf + "/init.el";
    defaultInitFile = true;
    package = pkgs.emacs-unstable-pgtk;
  };
in
  config = {
    nixpkgs.overlays = [
      emacs-overlay.overlays.emacs
    ];

    environment.systemPackages = [
      emacsWithPackages
    ];
  };
};
```

We can then compile the package ourselves:

```diff
 let
   emacsWithPackages = pkgs.emacsWithPackagesFromUsePackage {
     config = emacs-conf + "/init.el";
     defaultInitFile = true;
     package = pkgs.emacs-unstable-pgtk;
 
+    override = final: prev: {
+      bitwarden = final.melpaBuild {
+        pname = "bitwarden";
+        version = "0.1.0";
+        src = pkgs.fetchFromGitHub {
+          owner = "seanfarley";
+          repo = "emacs-bitwarden";
+          rev = "50c0078d356e0ac0bcaf26b40113700ba4123ec3";
+          hash = "sha256-5zAkoCdBDI7sNLtxOy4t91A4IGV84lD3Cz5nnsQ0P4Q=";
+        };
+      };
+    };
+  };
 in
   config = {
     nixpkgs.overlays = [
       emacs-overlay.overlays.emacs
     ];

     environment.systemPackages = [
       emacsWithPackages
+      pkgs.bitwarden-cli
     ];
   };
 };
```

## 3. Configure secret

Now we have an emacs with the emacs-bitwarden package loaded.
We can verify this by looking at `auth-sources`:

```elisp
(bitwarden "~/.authinfo" "~/.authinfo.gpg" "~/.netrc")
```

Now, in Magit, we can open a repository and try to create a pull request:

```
M-x forge-create-pullreq
```

After writing the description, I tried to create the pull request with `C-c C-c` but got this error message:

```
ghub--token: Required Github token
("ibizaman^forge" for either "api.github.com"
or "api.github.com") does not exist.
```

This tells me exactly what secret I need to add in Bitwarden.

First, let's create a PAT in Github in [](https://github.com/settings/personal-access-tokens)
with fine-grained permissions and give the following permissions:

- `Administration - write`
- `Pull Requests - write`

Now, we store this value in Bitwarden in a secret with:

- `Username` = `ibizaman^forge`
- `Password` = PAT from Github
- `Website` = `api.github.com`
- `Name` = Name can be anything of your choosing.

## Misc

A few more random tips.

### Clear auth-sources cache

Emacs aggressively caches secrets, even failure to find secrets.
Reset the cache with `M-x auth-source-forget-all-cached`.

### Self-hosted Bitwarden

To use a self-hosted Bitwarden or Vaultwarden, run on the command line:

```bash
bw config server https://<fqdn>
```

### Log into vault

To login into bitwarden, run on the command line:

```bash
bw login
```

or in emacs:

```elis
M-x bitwarden-login
```

### Unlock vault

Afterwards, you will need to unlock the vault with one of the following commands.
You will for example need to do this on reboot too.

```bash
bw unlock
```

or in emacs:

```elis
M-x bitwarden-unlock
```

### Sync vault

After updating a secret, to synchronize the vault, run either:

```bash
bw sync
```

or in emacs:

```elis
M-x bitwarden-sync
```
