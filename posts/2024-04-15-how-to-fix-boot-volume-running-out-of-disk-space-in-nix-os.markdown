---
title: How to fix /boot volume running out of disk space in NixOS
tags: nix
---

After a while without removing old generations, I got into a pickle.

# Situation

After running `colmena apply` to deploy to my server for the Nth time, I got this error:

```bash
Activation failed: Child process exited with error code: 1

[ERROR]   stderr) OSError: [Errno 28] No space left on
  device: '/nix/store/cwimj1bg0dgfvngdmbrapkp5ifl3bfgy-initrd-linux-6.6.22/initrd'
  -> '/boot/EFI/nixos/cwimj1bg0dgfvngdmbrapkp5ifl3bfgy-initrd-linux-6.6.22-initrd.efi'
```

Wait, no space left on the `/boot` volume? Uh oh. Taking a look, indeed it's full:

```bash
$ df -h /boot
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p1  128M  128M  2.0K 100% /boot
```

# Fix

Now, the trick is two-fold. First, we must delete old generations with old versions of the kernel.
As you can see, I didn't properly clean this up.

```bash
$ nix profile history \
    --profile /nix/var/nix/profiles/system
Version 1 (2024-03-31):
  No changes.

Version 2 (2024-03-31) <- 1:
  No changes.

Version 3 (2024-03-31) <- 2:
  No changes.

...

Version 111 (2024-04-11) <- 110:
  No changes.

Version 112 (2024-04-15) <- 111:
  No changes.
```

To remove old generations and allow the garbage collection to kick in, run:

```bash
$ sudo nix profile wipe-history \
    --profile /nix/var/nix/profiles/system \
    --older-than 14d
removing profile version 12
removing profile version 11
removing profile version 10
removing profile version 9
removing profile version 8
removing profile version 7
removing profile version 6
removing profile version 5
removing profile version 4
removing profile version 3
removing profile version 2
removing profile version 1
```

Followed by the garbage collection:

```bash
$ nix store gc
1855 store paths deleted, 1851.81 MiB freed
```

But that wasn't enough to get rid of the extraneous kernels.

```bash
$ sudo ls -l /boot/EFI/nixos
total 130308
-rwx------ 1 root root 10187264 Apr 15 06:15 0d3nlv97dyyflgq7irn5wy91x2mlszl3-linux-6.6.22-bzImage.efi
-rwx------ 1 root root 27904393 Apr 15 06:15 72p297y5a780hd6r5jwz0zqv4am97vpj-initrd-linux-6.6.22-initrd.efi
-rwx------ 1 root root 19864710 Apr 15 06:15 83i5i813jhsahlf7wmlbn96bngnjinf1-initrd-linux-6.6.22-initrd.efi
-rwx------ 1 root root 28606443 Apr 15 06:15 8bv13658nk7s12qljx0lch4g2bhrkvgr-initrd-linux-6.6.22-initrd.efi
-rwx------ 1 root root  8232960 Apr 15 06:15 cwimj1bg0dgfvngdmbrapkp5ifl3bfgy-initrd-linux-6.6.22-initrd.efi
-rwx------ 1 root root 27909504 Apr 15 06:15 ignpfyssa0ma4xp4asirfaq18f50vz8k-initrd-linux-6.6.22-initrd.efi
-rwx------ 1 root root 10723840 Apr 15 06:15 zqp81gm823adj6d6rk4k04gllhvwz847-linux-6.6.22-bzImage.ef
```

For that, we actually need to redeploy! So after one more `colmena apply`, which was successful this
time, I got rid of the old kernels:

```bash
$ sudo ls -l /boot/EFI/nixos
total 66414
-rwx------ 1 root root 10187264 Apr 15 06:35 0d3nlv97dyyflgq7irn5wy91x2mlszl3-linux-6.6.22-bzImage.efi
-rwx------ 1 root root 28577118 Apr 15 06:35 8bv13658nk7s12qljx0lch4g2bhrkvgr-initrd-linux-6.6.22-initrd.efi
-rwx------ 1 root root 29239767 Apr 15 06:35 cwimj1bg0dgfvngdmbrapkp5ifl3bfgy-initrd-linux-6.6.22-initrd.efi
```
