---
title: Install NixOS on a Raspberry PI
tags: server, nix
---

I am writing this blog post because, although all the documentation is available online, it is not
always obvious how all the parts should fit together.

<!--toc:start-->
- [Install NixOS](#install-nixos)
  - [Aside on WiFi](#aside-on-wifi)
- [Activate the System Manually](#activate-the-system-manually)
- [Configure SSH Public Key Access](#configure-ssh-public-key-access)
- [Remove SSH Password Access](#remove-ssh-password-access)
- [Deploy to the Raspberry PI with Colmena](#deploy-to-the-raspberry-pi-with-colmena)
- [Conclusion](#conclusion)
<!--toc:end-->

# Install NixOS

Follow the [Official NixOS on Raspberry Pi wiki](https://nixos.wiki/wiki/NixOS_on_ARM/Raspberry_Pi).
You should be able to download a pre-built image through Hydra which was nice. The guide will walk
you through writing the image to a SD card and booting up the PI for the first time.

After `configuration.nix` file gets generated on first boot, modify it to:

- Change the hostname.
  ```nix
  networking.hostName = "RPI_HOSTNAME";
  ```
- Enable ssh daemon, which automatically opens the port 22 in the firewall.
  ```nix
  services.openssh.enable = true;
  ```
- Add a `nixos` user that can sudo that will be used to deploy.
  ```nix
  users.users.nixos = {
    isNormalUser = true;
    # Enable ‘sudo’ for the user:
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      # ...
    ];
  };
  ```
  And enable sudo without entering the password.
  ```nix
  security.sudo.extraRules = [
    { users = [ "nixos" ];
      options = [ "NOPASSWD" ];
    }
  ];
  ```
  You can choose another user name here, no need to stick to `nixos`.

You should not need to modify the `hardware-configuration.nix` file.

## Aside on WiFi

If you need WiFi, check out my [blog post on using WiFi with
NixOS](./2023-05-15-declarative-wi-fi-with-encrypted-secret-on-nix-os.html). Like for this post, all
the documentation is out there but setting up WiFi declaratively with an encrypted secret is not
trivial.

If you connected the Raspberry PI with an Ethernet cable to the router, it should have automatically
setup access to the internet.

# Activate the System Manually

With a functioning internet connection, run:
```bash
sudo nixos-rebuild switch
```

Also, set a password for the user we just created.
```bash
passwd nixos
```

Note that if you chose another user name than `nixos`, the `nixos` user we were using until now does
not exist anymore. You will need to `exit` the session and login as the user we configured earlier.

In the rest of the post, I will assume you did stick to `nixos` so every time you see `nixos`,
replace it by the user name you chose.

# Configure SSH Public Key Access

Now, you can access the Raspberry PI using its IP address and the `nixos` user's password. We will
configure a private-public key pair instead and disable ssh password access.

On your laptop - not the Raspberry PI - run:

```bash
ssh-keygen -t ed25519 \
           -f ~/.ssh/RPI_HOSTNAME \
           -C "nixos@LAPTOP_HOSTNAME"
```

Personally, I do use a passphrase when generating the key and add the key to ssh-agent. I will add a
post about that later.

Now, copy over the public key with:

```bash
ssh-copy-id -i ~/.ssh/RPI_HOSTNAME RPI_IP_ADDRESS
```

And update your laptop's ssh config. Somewhere in your NixOS config you should add:

```nix
program.ssh.matchBlocks = {
    "RPI_HOSTNAME" = {
        user = "nixos";
        iidentityFile = "/home/ME/.ssh/RPI_HOSTNAME";
    };
};
```

Now, you can ssh in with `ssh RPI_HOSTNAME`.

# Remove SSH Password Access

It is not ideal to leave this, so add the following to the Raspberry PI's `configuration.nix`.

```nix
services.openssh.permitRootLogin = "no";
services.openssh.passwordAuthentication = false;
```

# Deploy to the Raspberry PI with Colmena

[Colmena](https://github.com/zhaofengli/colmena) is one of the existing ways to deploy a
configuration to a NixOS machine.

Add the machine to a `flake.nix`:

```nix
{
  outputs = {
    colmena = {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
        };
      };

      RPI_HOSTNAME = { name, nodes, ... }: {
        deployment = {
          # Must correspond to the hostname in the
          # ssh config.
          targetHost = "RPI_HOSTNAME";
          # Needed to build on the Raspberry PI
          # because the laptop is a x86 architecture.
          buildOnTarget = true;
          # The user that can do password-less sudo.
          targetUser = "nixos";
        };
        networking.hostName = name;
      
        # The configuration.nix file copied from the
        # Raspberry PI.
        imports = [
          ./machines/RPI_HOSTNAME-configuration.nix
        ];
      };
    };
  };
};
```

Copy over the Rasbpberry PI's `configuration.nix` and `hardware-configuration.nix` files to a local
`machines/` folder and reference the former in the import above. You should have the following
files:

- `flakes.nix` that imports
- `machines/RPI_HOSTNAME-configuration.nix` that imports
- `machines/RPI_HOSTNAME-hardware-configuration.nix`

Finally, run:

```bash
colmena apply
```

It should work for a few minutes - around 15 the first time in my case - then say "activation
successful".

# Conclusion

We just installed NixOS on a Raspberry PI and were able to deploy to it.
