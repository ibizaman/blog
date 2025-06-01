---
title: Qemu tips for cdrom, ide and nvme hard drives
tags: qemu, nix
---

<!--toc:start-->
- [Nix](#nix)
- [CDROM (sr0)](#cdrom-sr0)
- [Iso file in Nix](#iso-file-in-nix)
- [EFI](#efi)
- [SATA (sdX) drive](#sata-sdx-drive)
- [NVMe (nvmeX) drive](#nvme-nvmex-drive)
<!--toc:end-->

Qemu's documentation is a bit scattered around the web.

I managed to follow the [nvme][] documentation
but just couldn't find anything in [qemu.org][] about
SATA drives apart from some small snippets in other sections.

Some other examples could be found on StackOverflow.

This blog post regroups snippets geared towards concrete examples
to start a Qemu VM with EFI, SATA, NVMe and/or cdrom.

[nvme]: https://www.qemu.org/docs/master/system/devices/nvme.html
[qemu.org]: https://www.qemu.org

## Nix

You can test with:

```nix
nix run nixpkgs#qemu -- <options go here>
```

For EFI though, using the following script will help you to get easily the
needed firmware:

```nix
let
  nixos-qemu = pkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {};
  qemu = nixos-qemu.qemuBinary pkgs.qemu;
in
  pkgs.writeShellScriptBin "script" ''

  ${qemu} ... <options go here>
  '';
```

We purposely use the facilities provided by [qemu-common.nix][] because
all the wiring is done for us already for EFI and some options
matching our architecture are set.

[qemu-common.nix]: https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/qemu-common.nix#L35

## CDROM (sr0)

Assuming you have a ISO file available at `./iso`.
See [next section](#iso-file-in-nix) if you want to create an ISO file with nix.

```bash
--drive media=cdrom,format=raw,readonly=on,file=./iso
```

It will show up as `sr0`.

## Iso file in Nix

With [nixos-generators](https://github.com/nix-community/nixos-generators):

```nix
let
  iso = nixos-generators.nixosGenerate {
    inherit system;
    format = "install-iso";

    modules = [
    ];
  };
in
  <use 'iso' variable here>
```

## EFI

To boot using EFI, add:

```bash
--drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}
```

Here I'm using the [Nix snippet](#nix) to get the OVMF firmware.

## SATA (sdX) drive

With the following variable:

```bash
diskSata1=./diskSata1.qcow2
```

Create a drive:

```bash
${qemu} create -f qcow2 $diskSata1 20G
```

Then use it as a SATA drive:

```bash
--drive format=qcow2,file=$diskSata1,if=none,id=diskSata1 \
--device ide-hd,drive=diskSata1
```

Pay attention that the values for `id=` and `drive=` can be arbitrary
but must match.

It will show up as a `sdX` drive:

```bash
$ lsblk
sda
```

To add another drive as `sdb`, use the same method
but create a new file
and replace occurrences of `diskSata1` in `id=` and `drive=` with another value.

To specify the device name yourself,
add `serial=<name>` to the `--device` options.

## NVMe (nvmeX) drive

The method for NVMe drives is exactly the same as for [SATA][] drives
but replace `--device ide-hd,...` with `--device nvme,...`.

[SATA]: #sata-sdx-drive

## Epilogue

I'm using this in my project [Skarabox][] whose goal is to be the fastest
way to install NixOS on host with all bells and whistles included.

Specifically, I'm using a qemu VM to [test the installation](skarabox-test) on a VM.

[skarabox]: https://github.com/ibizaman/skarabox
[skarabox-test]: https://github.com/ibizaman/skarabox/blob/master/flakeModule.nix#L238
