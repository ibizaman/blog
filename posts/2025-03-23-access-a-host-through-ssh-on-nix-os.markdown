---
title: Access a Host Through SSH on NixOS
tags: nix, server
---

<!--toc:start-->
- [Scaffolding](#scaffolding)
- [Generate a SSH keypair](#generate-a-ssh-keypair)
- [Configuration for the Server Host](#configuration-for-the-server-host)
- [Configuration for the Client Host](#configuration-for-the-client-host)
- [Cleanup](#cleanup)
- [Conclusion](#conclusion)
<!--toc:end-->

Let's see how to grant ourselves ssh access
form a client host to a server host using NixOS.

This post assumes you can already deploy to the server host,
by means of another ssh key.
So this is not about bootstrapping a server.
Here, we'll see how to grant another user access to the host,
for example a backup user with reduced access.

## Scaffolding

For this post, I'll be using:

- flakes,
- [deploy-rs][] to deploy on the server host,
- [nixos-rebuild][] to deploy on the client host,
- [sops-nix][] to store the ssh private key encrypted
- and [home-manager][] to configure the client host.

[deploy-rs]: https://github.com/serokell/deploy-rs
[nixos-rebuild]: https://nixos.org/manual/nixos/stable/#sec-changing-config
[sops-nix]: https://github.com/Mic92/sops-nix
[home-manager]: https://github.com/nix-community/home-manager

This requires a bit of trial and error to get all these pieces to fit together,
so here is a flake that defines the scaffolding
for both the client and the server host:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, home-manager, sops-nix }: let
    system = "x86_64-linux";

    specialArgs = {
      serverUser = "vorta";
      clientUser = "me";
      serverHost = "server";
      clientHost = "client";
    };
  in {
    nixosModules.server = {
      imports = [
        sops-nix.nixosModules.default
        ./server.nix
      ];
    };

    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules = [ self.nixosModules.client ];
    };

    nixosModules.client = {
      imports = [
        home-manager.nixosModules.default
        sops-nix.nixosModules.default
        ./client.nix
      ];
    };

    nixosConfigurations.client = nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules = [ self.nixosModules.client ];
    };
  };
}
```

We use `specialArgs` here to pass arguments
to both the client and the server configuration
instead of copying values around.

Deploying to the server host is done with:

```nix
nix run nixpkgs#deploy-rs .#server

# Or, if deploy-rs is installed on your system:
deploy .#server
```

Deploying to the client host is done with:

```nix
sudo nixos-rebuild --flake . switch
```

## Generate a SSH keypair

This step is still manual:

```bash
nix shell nixpkgs#openssh --command \
  ssh-keygen -t ed25519 -f mykey
```

Pick no passphrase if you intend this user to get automated access.

This will create two files,
`mykey` with the private key
and `mykey.pub` with the public key.
We will use both in the later sections.

## Configuration for the Server Host

In this example, I create a new `vorta` user
to allow access for backups by the [VortaBackup][] software
into the folder `/srv/backup/vorta/me`.

[VortaBackup]: https://vorta.borgbase.com/

This goes in `./server.nix`:

```nix
{ config, serverUser, clientUser, ... }:
{
  users.users.${serverUser} = {
    isSystemUser = true;
    # Needed to be able to log in.
    useDefaultShell = true;

    home = "/srv/backup/${serverUser}/${clientUser}";
    homeMode = "770";
    createHome = true;
    group = "backup";

    isSystemUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAAA..."
    ];
  };
  users.groups.backup = {};
}
```

The `users.users.${serverUser}.openssh.authorizedKeys.keys` field
contains the public key from the `mykey.pub` file.

If you intend to keep the file laying around, you could instead do:

```nix
users.users.${serverUser}.openssh.authorizedKeys.keys = [
  (builtins.readFile ./mykey.pub)
];
```

Both versions give the same result and it's really a matter of taste here.

## Configuration for the Client Host

Copy the private key from `mykey` under some yaml field in your sops file.
I'll assume it's under `ssh/server/client-me-vorta`.
The convention is `ssh/${serverHost}/${clientHost}-${clientUser}-${serverHost}`
and is an organized to let me have multiple access per server-client pair.

This goes in `./client.nix`:

```nix
{ config, serverUser, clientUser, serverHost, clientHost, ... }:
{
  sops.secrets."ssh/${serverHost}/backup" = {
    owner = user;
    path = "/home/${clientUser}/.ssh/${serverHost}-${serverUser}";
    key = "ssh/${serverHost}/${clientHost}-${clientUser}-${serverHost}";
  };

  home-manager.users.${clientUser} = {
    programs.ssh = {
      enable = true;
      matchBlocks = {
        "${serverHost}-${serverUser}" = {
          user = serverUser;
          hostname = serverHost;
          identityFile = config.sops.secrets.
            "ssh/${serverHost}/backup".path;
        };
      };
    };
  };
}
```

I use the `key` field of sops-nix to give a nickname to the secret,
making it a bit easier to recall later in the `home-manager` config.
This is optional.

## Cleanup

The `mykey` files laying around this way is not good.
Let's delete them securely with the `shred` tool:

```bash
nix shell coreutils --command shred mykey
nix shell coreutils --command shred mykey.pub
rm mykey
rm mykey.pub
```

Omit the `mykey.pub` file if you used the `readFile` version of the code.

## Conclusion

After deploying, we now can access the server with the new user with:

```bash
ssh ${serverHost}-${serverUser}
```

With the example values I chose above, it's:

```bash
ssh server-vorta
```
