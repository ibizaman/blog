---
title: Recover NixOS System
tags: nix
---

<!--toc:start-->
- [Context](#context)
  - [Potential Harmful Change](#potential-harmful-change)
  - [Impossible to Recover](#impossible-to-recover)
  - [Did not Test](#did-not-test)
  - [Bonus Stress Inducing Factor](#bonus-stress-inducing-factor)
- [Recovery Overview](#recovery-overview)
  - [NixOS Recovery USB stick](#nixos-recovery-usb-stick)
  - [nixos-enter](#nixos-enter)
  - [flake](#flake)
  - [Update Configuration](#update-configuration)
  - [nixos-rebuild](#nixos-rebuild)
  - [Unmount Cleanly](#unmount-cleanly)
- [Takeaway](#takeaway)
<!--toc:end-->

# Context

I managed to brick my NixOS server. The recipe to achieve that is quite simple, just throw all best
practices out the window by doing the following three things at the same time:

1. Make a potentially harmful change.
2. Make it impossible to recover.
3. Do not test.

Pretty easy, right?

## Potential Harmful Change

My server has its root partition on an encrypted ZFS partition. This means I need to enter the
passphrase for my server to boot. To be able to ssh into the server and enter the passphrase
remotely, I had the [boot.initrd](https://search.nixos.org/options?query=boot.initrd) options setup
correctly.

But I wasn't happy with my setup. See, when I sshed in, the prompt to type the passphrase was shown,
I could then enter the passphrase and press Enter to mount the root partition, but I then had the
prompt still open and I needed to exit the prompt manually. This extra exit step was not to my liking. So I changed:

```bash
echo "zfs load-key zroot; killall zfs" \
  >> /root/.profile
```

to this:

```bash
echo "zfs load-key zroot; killall zfs" \
  >> /root/.profile; exit
```

instead of this:

```bash
echo "zfs load-key zroot; killall zfs; exit" \
  >> /root/.profile
```

See the mistake? The exit was not in the correct location! So instead of showing me the prompt to
unencrypt the partition, the startup would fail and I couldn't do anything about it.

## Impossible to Recover

I had been playing around with tweaking the boot initrd options for some time. Each time, it creates
a new voluminous file that lines inside `/boot`. I gave less than 1Gb disk space for that partition
so it fills up quickly during my tweaks.

I even made [another blog post][post] about how to recover from a filled up `/boot` partition already.

[post]: https://blog.tiserbox.com/posts/2024-04-15-how-to-fix-boot-volume-running-out-of-disk-space-in-nix-os.html

Anyway, I did what I wrote in that blog post and ran a command to remove old generations:

```bash
sudo nix profile wipe-history \
    --profile /nix/var/nix/profiles/system \
    --older-than 14d
```

But since that was not enough, I removed the `older-than` argument. This removed all previous
generations, as I wanted, but not as I should have done.

## Did not Test

`nixos-rebuild build-vm` is [a thing][buildvm] and I should learn to use this tremendously useful
feature. I already use NixOS VM tests quite extensively in my [Self Host Blocks][shb] project so I
have no excuse.

[buildvm]: https://wiki.nixos.org/wiki/NixOS:nixos-rebuild_build-vm
[shb]: https://github.com/ibizaman/selfhostblocks

## Bonus Stress Inducing Factor

Of course, I did this 24 hours before leaving on a trip. Why not?

# Recovery Overview

So, how do you recover from this? The quick overview that `@k900` from Matrix gave me is:

1. Boot on a NixOS Recovery USB stick
2. nixos-enter
3. change configuration
4. nixos-rebuild

I knew `nixos-enter` was a thing from the NixOS installation procedure but never would've thought
about using it to recover a system!

That being said, because I was using flakes, ZFS for the partitions and colmena to deploy, each step
had unforeseen complications. This blog posts goes over those and how I proceeded for each step.

## NixOS Recovery USB stick ##

Also called live CD. But how to make such a thing? [The wiki][cd] explains how to do this quite
well. And it's so easy, I love nix.

[cd]: https://wiki.nixos.org/wiki/Creating_a_NixOS_live_CD

Here's exactly how _I_ created the live CD:

```nix
nixosConfigurations.recovery-iso = let
  inherit (inputs) nixpkgs;
  system = "x86_64-linux";
in
  (nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"

      ({ config, pkgs, ... }: {
        boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

        environment.systemPackages = [
          pkgs.colmena
        ];
      })
    ];
  }).config.system.build.isoImage;
```

Since I wanted to work on ZFS partitions, I changed the kernel for a ZFS compatible one.

I also added the `colmena` package. You could avoid doing that as long as the machine you want to
recover has internet by running `nix shell nixpkgs#colmena` when booted in the recovery environment.

To build the CD:

```bash
nix build .#nixosConfigurations.recovery-iso
```

And finally to copy it on a USB stick on `/dev/sdb`:

```bash
sudo dd \
  bs=4M \
  status=progress \
  conv=fdatasync \
  if=./result/iso/nixos-24.05.20240421.6143fc5-x86_64-linux.iso \
  of=/dev/sdb
```

## nixos-enter ##

Again, the [wiki][root] explains well what to do in the general case.

[root]: https://wiki.nixos.org/wiki/Change_root

For this step, I needed to mount the ZFS partition called `zroot` and unencrypt it:

```bash
sudo zpool import zroot -f
sudo zfs load-key zroot
# <enter passphrase>
```

I could then mount the 3 required filesystems. That being said, because I did let ZFS mount them by
setting the `mountpoint` option, I couldn't just use `zfs mount` to mount them under the `/mnt`
directory. I needed instead
[this](https://github.com/openzfs/zfs/issues/4553#issuecomment-632068563):

```bash
sudo mount -t zfs -o zfsutil zpool/local/root /mnt
sudo mount -t zfs -o zfsutil zpool/local/nix /mnt/nix
sudo mount -t zfs -o zfsutil zpool/safe/home /mnt/home
```

Now, I could run `nixos-enter` and get chrooted under `/mnt`.

## flake ##

At this point, I should have been able to change `configuration.nix` but there is no such file when
using flakes! So instead, I needed a copy of my repository used to deploy this machine.

I could have copied it from my laptop but instead I went back out of the chrooted environment and
copied it over from an external hard drive used to store the repositories:

```bash
sudo zpool import data -f
zfs get keylocation data
cp /mnt/persist/data_passphrase /persist
sudo zfs load-key data
sudo mount -t zfs -o zfsutil data/nextcloud /mnt/srv/nextcloud

# Repo is now under /mnt/srv/nextcloud/.../nix-config
cp -r /mnt/srv/nextcloud/.../nix-config /mnt/root
```

The instructions above have additional steps compared to the root partition because those external
hard drives use a different passphrase that's only located on the ZFS root system. So I needed to
copy over the key to the location expected by ZFS.

## Update Configuration ##

Now, I could finally make the change to the repository!

```bash
nixos-enter
cd /root/nix-config
```

then change the incriminated line to:

```bash
echo "zfs load-key zroot; killall zfs; exit" \
  >> /root/.profile
```

## nixos-rebuild ##

Since I was not using `nixos-rebuild` to deploy in the first place, I could not run `nixos-rebuild`
to deploy locally either because there is no `nixosConfigurations` flake output. When using
`colmena` there is instead a `colmena` output. This meant I needed to:

1. Allow colmena to deploy locally this machine by enabling the
   [option](https://colmena.cli.rs/unstable/features/apply-local.html):

   ```nix
   deployment.allowLocalDeployment = true;
   ```

   I had not enabled that option yet for this machine since I never needed to deploy this
   configuration locally.

2. Run `colmena apply-local --node <mymachine> boot`.

But that failed because I did not mount the boot partition!

So, after getting out of the chroot once more, I mounted the correct boot partition:

```bash
cat /mnt/etc/fstab | grep boot
sudo mount /dev/disk/by-partlabel/disk-x-ESP /mnt/boot
```

Then I re-entered the chroot with `nixos-enter` and ran the following command which finally
succeeded.

```bash
colmena apply-local --node <mymachine> boot
```

## Unmount Cleanly ##

But wait! If you reboot now, the system will not be able to mount the ZFS partitions. You first need
to export the zpools:

```bash
sudo zpool export zroot
sudo zpool export data
```

If you forget this last step, just reboot on the USB drive and re-import the pools then export them.

Of course I forgot to do this on my first try.

# Takeaway

What was the takeaway here? It was never wracking and exhausting. Never again.
