---
title: Enable Hibernation on NixOS
tags: nix
---

Hibernation was broken for me since a long time.
I postponed trying to fix it for such a long time.
Then, I stumbled onto [this post](post) which had the fix!

[post]: https://discourse.nixos.org/t/hibernate-doesnt-work-anymore/24673/6?u=ibizaman

To celebrate the finding, I'm sharing a NixOS module
to enable hibernation.

As a prerequisite, you need to create a swap partition,
as noted in the [NixOS wiki](wiki).

[wiki]: https://wiki.nixos.org/wiki/Power_Management#Hibernation

As for the module, here it is:

```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.base;
in
{
  options.base = {
    hibernation = lib.mkOption {
      description = ''
        Options to configuration hibernation.
      '';
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "hibernation";

          device = lib.mkOption {
            type = lib.types.str;
            description = ''
              Device used to store hibernation
              information. Use lsblk to find it.
            '';
            example = "/dev/disk/by-label/swap";
          };

          hibernateAfterSleepDelay = lib.mkOption {
            type = lib.types.str;
            description = ''
              Hibernate after sleeping for this long.
            '';
            default = "2h";
          };
        };
      };
    };
  };

  config = {
    powerManagement.enable = true;

    # Specifies where the hibernation info will be stored.
    boot.kernelParams = [
      "resume=${cfg.hibernation.device}"
    ];

    # Allow hibernation
    security.protectKernelImage = !cfg.hibernation.enable;

    # Enable hibernation in menus
    environment.etc = lib.mkIf cfg.hibernation.enable {
      "/polkit-1/localauthority/50-local.d/com.ubuntu.enable-hibernate.pkla".text = ''
        [Re-enable hibernate by default in upower]
        Identity=unix-user:*
        Action=org.freedesktop.upower.hibernate
        ResultActive=yes

        [Re-enable hibernate by default in logind]
        Identity=unix-user:*
        Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.handle-hibernate-key;org.freedesktop.login1;org.freedesktop.login1.hibernate-multiple-sessions;org.freedesktop.login1.hibernate-ignore-inhibit
        ResultActive=yes
        '';
    };

    # Set suspend-then-hibernate as defaults
    services.logind = lib.mkIf cfg.hibernation.enable {
      lidSwitch = "suspend-then-hibernate";
      extraConfig = ''
        HandlePowerKey=suspend-then-hibernate
        IdleAction=suspend-then-hibernate
        IdleActionSec=2m
      '';
    };

    # 
    systemd.sleep.extraConfig = lib.mkIf cfg.hibernation.enable
      "HibernateDelaySec=${cfg.hibernation.hibernateAfterSleepDelay}";
  };
}
```

Happy hibernation!
