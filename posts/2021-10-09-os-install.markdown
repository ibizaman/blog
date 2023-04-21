---
title: OS Install
tags: server
---

This is obviously the first step, we will install the OS. I chose
Archlinux. Everything here should be adaptable to other linux
distributions but the locations of files could be different.

We'll create a live USB, use it to install Arch on another server and
we'll finish by SSHing to the server using SSH keys for
authentication.

# Preliminaries

We need to choose a few things before starting the install. Here is
what I'll stick to in this blog post:

- hostname of the server: `$server`
- hostname of the laptop you're currently using: `$laptop`
- user I'll use to connect to it: `$user`

I confess, there's nothing original here but I feel like it's easier
to follow along this way. I use the convention of bash variables with
the dollar prefix in the following.

# Live USB

First step is to create a bootable USB that we'll use to install Arch
on the server. We'll create two partitions, one for the OS, one for
storing some files like a SSH public key that will allow us to SSH
into the server without password.

The most up-to-date instructions are, like always, on the [Arch
wiki](https://wiki.archlinux.org/title/USB_flash_installation_medium).
But read along to know what _I_ did.

## Download the Arch ISO

From [https://archlinux.org/download/](https://archlinux.org/download/).

## Find the USB drive path

```
$ lsblk -p -d -o NAME,MODEL,SIZE,TRAN \
    | grep 'NAME\|usb'
```

Example output:

```
NAME         MODEL               SIZE TRAN
/dev/sda     ST9500325ASG      465.8G sata
/dev/nvme0n1 SPCC M.2 PCIe SSD 953.9G nvme
```

In the following, I'll use `/dev/sdX` as the path. Replace it by the
one you got from the command above.

## Partition and format the USB drive

Create two partitions, the first one must be `fat32`, the second
`ext4`.

```
$ fdisk /dev/sdX <<EOF
g    # use gpt table
n    # create new partition
1    # partition number
     # accept default
+3G  # 3Gb, adapt to your USB key size
t    # Change type of partition
1    #
n    # create new partiton
2    # partition number


p    # print table, to double check
w    # write table
EOF

$ mkfs.vfat -F32 /dev/sdX1
$ mkfs.ext4 -F /dev/sdX2
```

## Write OS and files to USB drive

Mount the two partitions and the Arch ISO.

```
$ mkdir -p mnt/root mnt/data mnt/iso
$ mount -o rw /dev/sdX1 mnt/root
$ mount -o rw /dev/sdX2 mnt/data
$ mount -o loop arch.iso mnt/iso
```

Copy the files to the root partition.

```
$ rsync -a \
    --info=progress2 \
    --human-readable \
    --no-inc-recursive \
    mnt/iso \
    mnt/root
```

Create a SSH private key and public key pair and copy it to the USB
key. I use `Password Store` as my password manager to generate and
store the passphrase.

```
$ pass generate --clip sshkey-passphrase/$laptop/$server

$ ssh-keygen -b 4096 -i ~/.ssh/$server -N $(pass show sshkey-passphrase/$laptop/$server)
$ cp ~/.ssh/$server.pub mnt/data
```

I use the convention `sshkey-passphrase/$laptop/$server` for the
location of the passphrase in my password manager.

Update the syslinux install to instruct the OS where the root
partition is located.

```
$ uuid=$(blkid -o value -s UUID "/dev/sdX1")
$ sed -i -e \
    "s|archisolabel=.*$|archisodevice=/dev/disk/by-uuid/$uuid|" \
    "mnt/root/arch/boot/syslinux/archiso_sys.cfg"
$ syslinux-install_update -iam
```

Don't forget to sync to actually write the files. This step can take a
while.

```
$ sync
```

Now, let's unmount and we can then remove the USB drive.

```
$ umount mnt/*
```

# Install OS on the server

Let's put the USB key in the server's USB port and boot the server.
I'll assume you have brand new drives or are happy to wipe them clean.


# TODO

GnuPG setup for ssh agent
