---
title: Switch to Colmena for Local Deploys
tags: nix
---

The [Incentive](#incentive) section explains why I even wanted to do this. Feel free to skip to [][]

<!--toc:start-->
- [Incentive](#incentive)
<!--toc:end-->

# Incentive

I've been deploying to my two server boxes with [Colmena](https://colmena.cli.rs/unstable/) since a
few months now and I'm very happy.

My laptop is using NixOS and I've been "deploying" to it using `nixos-rebuild switch` since the
start.

Recently, I wanted to mount a webdav folder from one of my servers to my laptop, to do that I
created a NixOS module (more on that in a later post) that sets up the following systemd mount:

```ini
$ systemctl cat home-me-mymount.mount 
# /etc/systemd/system/home-me-mymount.mount

[Unit]
After=network-online.target
Description=Webdav mount point
Wants=network-online.target

[Mount]
Options=uid=1000
TimeoutSec=15
Type=davfs
What=https://mydomain.com/webdav/mount
Where=/home/me/mymount
```

I then tried to start the mount:

```bash
$ sudo systemctl start home-me-mymount.mount 
systemd[1]: Mounting Webdav mount point...
mount.davfs[1231360]: davfs2 1.7.0
mount.davfs[1231360]: opening /etc/davfs2/secrets failed
systemd[1]: home-me-mymount.mount: Mount process exited, code=exited, status=255/EXCEPTION
systemd[1]: home-me-mymount.mount: Failed with result 'exit-code'.
systemd[1]: Failed to mount Webdav mount point.
```

Right, we need to create a file at `/etc/davfs2/secrets` with the password needed to access the
Webdav folder.

I obviously didn't want to create this file by hand. Also, I want this secret to be stored encrypted and be deployed in the correct place. We're using Nix after all and those are good practices.

I have been using [sops-nix](https://github.com/Mic92/sops-nix) to deploy secrets with great success and declaring this secrets looks like so using `sops-nix`:

```nix
sops.secrets."webdav" = {
  sopsFile = ./secrets.yaml;
  mode = "0600";
  path = "/etc/davfs2/secrets";
};
```

The snippet above is only half of the job though, the remaining part is actually creating the
`secrets.yaml` and encrypting it. I'll leave that out of this blog post as it's not relevant here.
Also, everything is explained in the `sops-nix` repo's readme file.

The issue here is we can't use `nixos-rebuild` to deploy keys with `sops-nix` or any other key
management system. You need to switch to `nixops`, `colmena` or any other such deploy system listed
[here](https://nixos.wiki/wiki/Applications#Deployment).

# Switching From Nixos-Rebuild to Colmena

Colmena allows you to use to [deploy
locally](https://colmena.cli.rs/unstable/features/apply-local.html) and switching to it is pretty
easy in my case. This was the flake output related to my laptop before:

```diff
- nixosConfigurations.mylaptop = nixpkgs.lib.nixosSystem {
-   inherit system;
-   specialArgs = {
-     inherit nixpkgs;
-   };
-   modules = [
-     inputs.home-manager.nixosModules.default
-     ./machines/laspin-configuration.nix
-     ./machines/laspin-home.nix
-   ];
- };
```

I removed those lines and created the following ones:

```diff
colmena = {
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
    };
    specialArgs = inputs;
  };
+  mylaptop = {
+    deployment = {
+      # Allow local deployment with `colmena apply-local`
+      allowLocalDeployment = true;
+
+      # Disable SSH deployment. This node will be skipped in a
+      # normal `colmena apply`.
+      targetHost = null;
+    };
+
+    imports = [
+      inputs.home-manager.nixosModules.default
+      inputs.sops-nix.nixosModules.default
+      ./machines/laspin-configuration.nix
+      ./machines/laspin-home.nix
+    ];
+  };
};
```

I just copy pasted the `modules` field to the `imports` field, added the `deployment` field to tell
colmena to deploy locally, added the `sops-nix` module because of my use case and... That was it!

Note that for Colmena matches the hostname with the attribute name `mylaptop`. I actually have `networking.hostName = "mylaptop";` set in my config.

To deploy on my laptop, I switched from:

```bash
$ sudo nixos-rebuild switch
```

to:

```bash
$ colmena apply-local --sudo
```

Which created the secret file I needed in the first place:

```bash
$ readlink /etc/davfs2/secrets 
/run/secrets/webdav
```
