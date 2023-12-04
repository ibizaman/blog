---
title: Deploy to NixOS With Colmena and Without Root User
tags: nix
---

By default, you use the root user to deploy to a target machine. If you want to avoid that, you can
create another user but getting all the configuration right is not obvious. So here's a rundown in 3 steps.

# 1. Create User

First, you need to create the user and make it able to run sudo without requiring a password. Let's
pick the username `nixos`. The hammer way of doing it is allowing all commands to be ran with sudo
without password.

```nix
users.users.nixos = {
  isNormalUser = true;
};

security.sudo.extraRules = [
  { users = [ "nixos" ];
    commands = [
      { command = "ALL";
        options = [ "NOPASSWD" ];
      }
    ];
  }
];
```

If you don't do that, you'll stumble in the following error and the build fails right afterwards:

> `sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper`

# 2. User Must be Trusted by Nix

Second, you must make the user a trusted user. On the target machine's configuration, add:

```nix
nix.settings.trusted-users = [ "nixos" ];
```

Otherwise, although you will be able to copy derivations over to the target machine, you won't be
allowed to talk to the nix daemon to add them to the nix store:

> `error: cannot add path '/nix/store/00yiiplzcqzmqaw10cghbxlb4l4xibc0-i3lock-color.pam' because it lacks a signature by a trusted key`

# 3. Make Deploy System Use New User

This step will depend on which system you use. For [Colmena][2], add the following option in the
target's configuration:

[2]: https://colmena.cli.rs/

```nix
deployment.targetUser = "nixos";
```

