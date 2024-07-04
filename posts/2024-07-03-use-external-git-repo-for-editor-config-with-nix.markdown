---
title: Using an External Git Repo for my Emacs Config with Nix
tags: nix
---

<!--toc:start-->
- [Context](#context)
- [Flake Input](#flake-input)
- [Give the Inputs to the NixOS Configuration](#give-the-inputs-to-the-nixos-configuration)
  - [NixOS with nixos-rebuild](#nixos-with-nixos-rebuild)
  - [Darwin](#darwin)
  - [NixOS with colmena](#nixos-with-colmena)
- [Common Config](#common-config)
- [In Practice](#in-practice)
<!--toc:end-->

## Context

So I have [this repository][repo] for my Emacs config.
How can I make NixOS aware of it and copy the files in the correct location?

[repo]: https://github.com/ibizaman/emacs-conf

## Flake Input

First step, putting the repo as a Nix flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    emacs-conf.url = "github:ibizaman/emacs-conf";
    emacs-conf.flake = false;

    emacs-overlay.url = "https://github.com/nix-community/emacs-overlay/archive/master.tar.gz";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

I'm using the [Emacs Overlay][overlay-repo] because it has quite a lot of goodies, like native compilation of elisp files.

[overlay-repo]: https://github.com/nix-community/emacs-overlay

## Give the Inputs to the NixOS Configuration

It's not exactly obvious how to take these inputs and give them to the modules.
Here's how to do it in some common situations.

### NixOS with nixos-rebuild

For a NixOS box:

```nix
{
  outputs = inputs@{ self, nixpkgs, ... }: {
    nixosConfigurations.machine =
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit (inputs) emacs-conf;
        };
        modules = [
          ./machine.nix
        ];
      };
  };
}
```

### Darwin

For a Darwin box, first you need a new input:

```nix
{
  inputs = {
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };
}

```

Then you can define it like so.

```nix
{
  outputs = inputs@{ self, nixpkgs, nix-darwin, ... }: {
    darwinConfigurations.machine =
      nix-darwin.lib.darwinSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit (inputs) emacs-conf;
        };
        modules = [
          ./machine.nix
        ];
      };
  };
}
```

### NixOS with colmena

```nix
{
  outputs = inputs@{ self, nixpkgs, ... }: {
    colmena = {
      meta = {
        specialArgs = {
          inherit (inputs) emacs-conf;
        };
      };
      machine = {
        imports = [
          ./machine.nix
        ];
      };
    };
  };
}
```

## Common Config

The content of `machine.nix` is:

```nix
{ config, pkgs, lib, inputs, ... }:

let
  emacsWithPackages = pkgs.emacsWithPackagesFromUsePackage {
    config = inputs.emacs-conf + "/init.el";
    defaultInitFile = true;
    package = pkgs.emacs-unstable;
  };
in

{
  config = {
    environment.systemPackages = [
      emacsWithPackages
    ];

    services.emacs = {
      enable = true;
      package = emacsWithPackages;
    };
  };
}
```

## In Practice

To update my Emacs config on my NixOS machine, I:

- Push a new commit to the Emacs repo.
- Run `nix flake lock --update-input emacs-conf`
- Run `nixos-rebuild switch`

Assuming I cloned my Emacs repo locally at `~/Projects/emacs-conf`,
I can also test a change by modifying the `init.el` file
then updating my config with the following command:

```bash
nix flake lock \
  --update-input emacs-conf \
  --override-input emacs-conf ~/Projects/emacs-conf
```

For Emacs configs specifically, I actually also test my config just by loading the code I modified.
Emacs being a Lisp machine, updating a function definition is easy.

In an elisp file, I can `C-c C-c` on a Lisp expression to evaluate it and load it with the following snippet:

```lisp
(defun eval-point-region-and-deactivate ()
  "Evaluate region or expanded region and deactivates region when done."
  (interactive)
  (use-region-or-expand-region)
  (condition-case-unless-debug err
      (message "%s" (call-interactively 'eval-region))
    (error (deactivate-mark)
           (signal (car err) (cdr err))))
  (deactivate-mark))


(use-package elisp-mode
  :config
  (define-key lisp-mode-map (kbd "C-c C-c")
              #'eval-point-region-and-deactivate))
```
