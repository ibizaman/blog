---
title: ZFS on NixOS
tags: nix, zfs
---

I resisted long enough. Having bought two new hard drives, I had a good enough reason to switch over
from LVM + mdadm.

This blog post is as much a memo for myself than a terse guide to people wanting to try ZFS.

## Partitioning

From
[https://openzfs.github.io/openzfs-docs/Project%20and%20Community/FAQ.html#performance-considerations](https://openzfs.github.io/openzfs-docs/Project%20and%20Community/FAQ.html#performance-considerations)

> Create your pool using whole disks: When running zpool create use whole disk names. This will
> allow ZFS to automatically partition the disk to ensure correct alignment. It will also improve
> interoperability with other OpenZFS implementations which honor the wholedisk property.

From [https://wiki.archlinux.org/title/ZFS#Storage_pools](https://wiki.archlinux.org/title/ZFS#Storage_pools) there's mixed messaging.

> It is not necessary to partition the drives before creating the ZFS filesystem. It is recommended
> to point ZFS at an entire disk (ie. /dev/sdx rather than /dev/sdx1), which will automatically
> create a GPT (GUID Partition Table) and add an 8 MB reserved partition at the end of the disk for
> legacy bootloaders.

while a bit later:

> The OS does not generate bogus partition numbers from whatever unpredictable data ZFS has written
> to the partition sector, and if desired, you can easily over provision SSD drives, and slightly
> over provision spindle drives to ensure that different models with slightly different sector
> counts can zpool replace into your mirrors.

From [https://forums.freebsd.org/threads/zfs-whole-disk-vs-gpt-slice.62855/](https://forums.freebsd.org/threads/zfs-whole-disk-vs-gpt-slice.62855/)

That user posted some good links. It seems using partitions is totally fine. That anyway, giving a
full disk to ZFS on Linux will create a GPT partition anyway.

I will try with partitions and by naming them with GPT labels. Labels are great because they are
unique and can convey meaning.

```bash
$ nix shell nixpkgs#gptfdisk

$ sudo fdisk -l

...

Disk /dev/sdb: 10.91 TiB, 12000138625024 bytes, 23437770752 sectors
Disk model: G
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes


Disk /dev/sdc: 10.91 TiB, 12000138625024 bytes, 23437770752 sectors
Disk model: G
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes
```

```bash
$ sudo gdisk -l /dev/sdb
Command (? for help): n
Partition number (1-128, default 1):
First sector (34-23437770718, default = 2048) or {+-}size{KMGTP}:
Last sector (2048-23437770718, default = 23437768703) or {+-}size{KMGTP}: -1G
Current type is 8300 (Linux filesystem)
Hex code or GUID (L to show codes, Enter = 8300):

Command (? for help): c
Using 1
Enter name: ZFSmirror1

Command (? for help): p
Disk /dev/sdb: 23437770752 sectors, 10.9 TiB
Model: G               
Sector size (logical/physical): 512/4096 bytes
Disk identifier (GUID): BEA1BE33-E007-4582-B29F-7952D9EE8E26
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 23437770718
Partitions will be aligned on 2048-sector boundaries
Total free space is 2099166 sectors (1025.0 MiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048     23435673566   10.9 TiB    8300  ZFS data mirror 1

Command (? for help): w

Final checks complete. About to write GPT data. THIS WILL OVERWRITE EXISTING
PARTITIONS!!

Do you want to proceed? (Y/N): Y
OK; writing new GUID partition table (GPT) to /dev/sdb.
The operation has completed successfully.
```

I then did the same with `/dev/sdc`.

I chose a label name with no space otherwise spaces gets replaced with `\x20` which gives names
like: `'ZFS\x20data\x20mirror\x201'`. No thanks.

```bash
$ ls -1 /dev/disk/by-partlabel/
ZFSmirror1
ZFSmirror2
```

## Enable ZFS on the machine

From [https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/](https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/) :

```nix
boot.supportedFilesystems = [ "zfs" ];
```

> `boot.zfs.forceImportRoot` is enabled by default for backwards compatibility purposes, but it is
> highly recommended to disable this option, as it bypasses some of the safeguards ZFS uses to
> protect your ZFS pools.

```nix
boot.zfs.forceImportRoot = false;
```

`networking.hostId` should be unique per machine. The primary use case is to ensure when using ZFS
that a pool isn’t imported accidentally on a wrong machine.

```nix
networking.hostId = "3d6f479a";
```

## Create zpool

From [https://openzfs.github.io/openzfs-docs/Project%20and%20Community/FAQ.html#performance-considerations](https://openzfs.github.io/openzfs-docs/Project%20and%20Community/FAQ.html#performance-considerations) I got that a good argument is:

  - `-o ashift=12`

Also:

> Have enough memory: A minimum of 2GB of memory is recommended for ZFS. Additional memory is
> strongly recommended when the compression and deduplication features are enabled.

From [https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/,](https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/,) I got:

  - `-o ashift=12`
  - `-o xattr=sa`
  - `-o compression=lz4`
  - `-o atime=off`
  - `-o recordsize=1M`

I won't be using a SLOG as this zpool will hold pictures and documents, so large files. Also no
L2ARV for me as I don't have that much RAM available.

From [https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html](https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html)

  - `-o ashift=12`
  - `-o autotrim=on`
  - `-O acltype=posixacl`
  - `-O canmount=off`
  - `-O dnodesize=auto`
  - `-O normalization=formD`
  - `-O relatime=on`
  - `-O xattr=sa`
  - `-O mountpoint=none`

About dnodesize:

> Consider setting dnodesize to auto if the dataset uses the xattr=sa property setting and the
> workload makes heavy use of extended attributes. This may be applicable to SELinux-enabled
> systems, Lustre servers, and Samba servers, for example. Literal values are supported for cases
> where the optimal size is known in advance and for performance testing.

> Leave dnodesize set to legacy if you need to receive a send stream of this dataset on a pool that
> doesn't enable the large_dnode feature, or if you need to import this pool on a system that
> doesn't support the large_dnode feature.

My final command was:

```bash
$ nix shell nixpkgs#gptfdisk
$ zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O encryption=on \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    -O compression=lz4 \
    -O canmount=off \
    -O mountpoint=/srv \
    -O xattr=sa \
    -O atime=off \
    -O acltype=posixacl \
    -O recordsize=1M \
    data \
    mirror \
    /dev/disk/by-partlabel/ZFSmirror1 \
    /dev/disk/by-partlabel/ZFSmirror2
```

This command will ask you for a passphrase.

```bash
$ zpool status -v
  pool: data
 state: ONLINE
config:

        NAME          STATE     READ WRITE CKSUM
        data          ONLINE       0     0     0
          ZFSmirror1  ONLINE       0     0     0
          ZFSmirror2  ONLINE       0     0     0

errors: No known data errors
```

I chose legacy mountpoint just so I could mount them manually in a temporary directory and transfer
over what needed to be.

```bash
$ sudo zfs create -o mountpoint=legacy data/nextcloud
$ sudo zfs create -o mountpoint=legacy data/git
```

## Quotas

Nothing fancy here but I wanted to put some.

From [https://docs.oracle.com/cd/E23823_01/html/819-5461/gazvb.html:](https://docs.oracle.com/cd/E23823_01/html/819-5461/gazvb.html:)

```bash
$ sudo zfs set quota=4T data/nextcloud
$ sudo zfs set quota=40G data/git
```

It can also be done at creation by using `-o quote=<size>`.

## Reservation for Performance

From [https://web.archive.org/web/20161028084224/http://www.solarisinternals.com/wiki/index.php/ZFS_Best_Practices_Guide#Storage_Pool_Performance_Considerations](https://web.archive.org/web/20161028084224/http://www.solarisinternals.com/wiki/index.php/ZFS_Best_Practices_Guide#Storage_Pool_Performance_Considerations) :

> Keep pool space under 80% utilization to maintain pool performance. Currently, pool performance
> can degrade when a pool is very full and file systems are updated frequently, such as on a busy
> mail server. Full pools might cause a performance penalty, but no other issues. If the primary
> workload is immutable files (write once, never remove), then you can keep a pool in the 95-96%
> utilization range. Keep in mind that even with mostly static content in the 95-96% range, write,
> read, and resilvering performance might suffer.

For my workload, I chose roughly 90%, so I'll reserve 1Tb from the ~12Tb available.

From [https://docs.oracle.com/cd/E23823_01/html/819-5461/gazvb.html](https://docs.oracle.com/cd/E23823_01/html/819-5461/gazvb.html) :

```bash
$ sudo zfs set reservation=1T data
```

## Transfer data

Mount new pool to a temporary directory under a temporary root `/pool` directory, then copy over
with `rsync`.

```bash
$ sudo mount -t zfs data/nextcloud /pool/nextcloud
$ sudo rsync -aHP /srv/data/nextcloud/ /pool/nextcloud
```

## Mount in correct location

```bash
$ sudo umount /srv/nextcloud
$ sudo zfs set mountpoint=/srv/nextcloud data/nextcloud
```

Setting the mountpoint this way will let ZFS mount the pool.

## Reboot

Because we encrypted the zpool, On reboot, you need to run:

```bash
$ sudo zpool import data
$ sudo zfs load-key data
$ sudo zfs mount -a
```

There are ways to automate this like [remote unlocking](https://wiki.nixos.org/wiki/ZFS#Remote_unlock).

## Next

Next will be snapshots and automating mounting after reboots.
