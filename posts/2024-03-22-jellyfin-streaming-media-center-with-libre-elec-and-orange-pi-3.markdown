---
title: Jellyfin Streaming Media Center with LibreElec and Orange PI 3
tags: jellyfin, iot
---

[Libreelec][libreelec] is a Linux distribution optimized to run [Kodi][kodi]. I installed it on an
[Orange Pi 3 LTS][orangepi-product] which is connected to my TV. I then installed the Jellyfin
plugin and can play all my media from Jellyfin on the TV.

To boost performance, I installed the distribution on the internal flash eMMC storage instead of
keeping it on the SD card.

This blog post covers everything I did to set this up.

[libreelec]: https://libreelec.tv/
[kodi]: https://kodi.tv/
[orangepi-product]: https://www.amazon.com/gp/product/B09TQZH4GJ/ref=ppx_yo_dt_b_search_asin_title?ie=UTF8&psc=1

![Orange Pi 3 LTS Allwinner H6 2GB LPDDR3 8GB EMMC Flash Quad Core](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/amazon.png "Amazon screenshot")

## Install Libreelec on an SD card

Go to [libreelec.tv][libreelec] > Downloads > Manual Downloads section > Allwinner > Allwinner H6 > Orange Pi 3 LTS

Of course, that's if you have an Orange Pi 3 LTS. Otherwise, pick the [correct
download][libreelec-download]. To burn on SD card, we will follow the [Archlinux
wiki][burn-sdcard-wiki].

[libreelec-download]: https://libreelec.tv/downloads/
[burn-sdcard-wiki]: https://wiki.archlinux.org/title/USB_flash_installation_medium#Using_basic_command_line_utilities

1. Put the SD card in your computer.
2. Use `lsblk` to identify the path to your SD card.

   In the following example, the path is `/dev/sda`.

```nix
$ lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda           8:0    1  29.1G  0 disk 
└─sda1        8:1    1  29.1G  0 part
nvme0n1     259:0    0 931.5G  0 disk 
├─nvme0n1p1 259:1    0 923.6G  0 part /nix/store
│                                     /
├─nvme0n1p2 259:2    0   7.5G  0 part [SWAP]
└─nvme0n1p3 259:3    0   487M  0 part /boot
```

3. Burn Libreelec on the SD card.

   Watch out, this will erase anything on the target path. In the following snippet, replace
   `/dev/sdX` with the path you got from the `lsblk` output.

```bash
$ gunzip --to-stdout \
    LibreELEC-H6.arm-11.0.3-orangepi-3-lts.img.gz \
  | sudo dd bs=4M conv=fsync oflag=direct \
            status=progress of=/dev/sdX

30+1 records in
30+1 records out
128064485 bytes (128 MB, 122 MiB) copied, 10.7377 s, 11.9 MB/s
```

4. Verify the partition layout looks like the following.

   Don't worry if the second partition does not cover the whole of the SD card, Libreelec will
   resize the partition on first boot.

```bash
$ sudo fdisk -l /dev/sda
Disk /dev/sda: 29.13 GiB, 31281119232 bytes, 61095936 sectors
Disk model: USB DISK        
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x9a55c0c3

Device     Boot   Start     End Sectors  Size Id Type
/dev/sda1  *       8192 1056767 1048576  512M  c W95 FAT32 (LBA)
/dev/sda2       1056768 1122303   65536   32M 83 Linux
```

## First boot

Put the SD card in the Orange PI - or any other [compatible device][libreelec-download] you have.

Connect the HDMI to your TV and connect a keyboard. The SD card will only be needed for the first
boot, the keyboard for the first and second. You could do without a keyboard by using a remote
control but that will be probably hard to type with.

![Upon booting LibreElec for the first time, it will resize the second partition then reboot once.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_resize.jpg "Picture of screen with LibreElec having resized the SD card and showing a countdown before rebooting."){.zoom}

You will then boot into the Jellyfin UI and the installation wizard will popup automatically.

![Wizard showing language selection. Pick a language.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_wizard_language.jpg){.zoom}

Next page will allow you to choose a hostname. I chose "tvlivingroom". Do not use special characters
nor whitespaces as those are not accepted. The wizard is poorly done here because if you enter a not
accepted character, no error message will be shown but you will be shown again the hostname
selection screen.

![Wizard showing network selection. Pick an Ethernet or WiFi connection.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_wizard_network.jpg){.zoom}

![Wizard showing ssh server toggle. Enable SSH server.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_wizard_ssh.jpg){.zoom}

You will need to wait about 10 seconds for the popup to appear to let you change the password. Later
on, we will configure only connect with a SSH key and not password.

![Wizard showing ssh server password. Choose a password.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_wizard_ssh_password.jpg){.zoom}

That should be then end of the wizard.

Now, we need to connect through SSH but to do that, we need to find the IP of this device. To do that, go to the settings page by clicking on the gear.

![Gear button to go to the settings page.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_ip_gear.jpg){.zoom}

Then on the settings page, go to the System Information page.

![Button to go to the System Information page.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_ip_menu.jpg){.zoom}

Finally, you will see the IP address of the device. In the following examples, we'll take `192.168.1.10`.

![System Information page showing the IP address of the device.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_ip_show.jpg){.zoom}

Now, connect through SSH using that IP. If you kept the default password above, use `libreelec` as
the password. Otherwise, use the one you entered.

```bash
$ ssh root@192.168.1.10 -o IdentitiesOnly=yes
root@192.168.1.10's password: 
##############################################
#                 LibreELEC                  #
#            https://libreelec.tv            #
##############################################

LibreELEC (official): 11.0.4 (H6.arm)
tvlivingroom:~ # 
```

We will install Libreelec on the eMMC memory. You can skip this step but I recommend going through
it as it drastically improves the performance of the UI.

```bash
tvlivingroom:~ # install2emmc

===============================
Installing LibreELEC to eMMC
===============================

eMMC found at /dev/mmcblk1


WARNING: ALL DATA ON eMMC WILL BE ERASED! Continue (y/N)?  y
Erasing eMMC ...
Creating partitions
Creating filesystems
Installing bootloader
Copying system files
Adjusting partition UUIDs
Done
```

Now, shutdown the device.

```bash
tvlivingroom:~ # shutdown -hP now
```

## Second boot

Remove SD card then start the device by pressing the button a couple seconds.

Now, the not fun part is you will need to redo the whole wizard setup. Go back to the previous
section if you need a refresher but skip the part where you install to the eMMC memory. Continue
from here when that's done.

## SSH access

Okay, on your laptop, generate an ssh key. I use an SSH agent to remember the passphrase of my SSH
keys so I do use a passphrase. If you don't want to use a passphrase, just leave it empty when you
get prompted.

1. Generate a random passphrase
```bash
$ openssl rand -hex 32
XYZ...
```

2. Generate an SSH key.
```bash
$ ssh-keygen -t ed25519 -f ~/.ssh/tvlivingroom
Generating public/private ed25519 key pair.
Enter passphrase (empty for no passphrase): 
Enter same passphrase again:
[...]
```

3. Add the key to the agent.
```bash
$ ssh-add ~/.ssh/tvlivingroom
```

4. Copy the key to the device.
```bash
$ ssh-copy-id -i ~/.ssh/tvlivingroom.pub -o IdentitiesOnly=yes root@192.168.1.20
```

5. You could SSH to the device with the following command, but it's quite long, so skip to the next step.
```bash
$ ssh -i ~/.ssh/tvlivingroom.pub root@192.168.1.10
```

6. Create a match block in `~/.ssh/config`:
```bash
Host salon
  User root
  HostName 192.168.50.201
  IdentityFile /home/timi/.ssh/salon 
```

   Or, if you're using Home Manager, this snippet would do the trick:
```bash
home-manager.users.me = {
  programs.ssh = {
    matchBlocks = {
      "tvlivingroom" = {
        user = "root";
        identityFile = "/home/me/.ssh/tvlivingroom";
        hostname = "192.168.1.10";
      };
    };
  };
};
```

Success, we can now connect with:

```bash
$ ssh tvlivingroom
```

## Harden device

Now, we can change the root password and restrict access to ssh key only.

I generate a new login/password combo with Bitwarden, then ssh on the Orange Pi and change the
password with:

```bash
$ ssh tvlivingroom
tvlivingroom:~ # passwd
Changing password for root
New password: 
Retype password: 
passwd: password for root changed by root
```

Now, we can remove password login through ssh by going through the UI:

![Button to access the SSH password menu.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_ssh_menu.jpg){.zoom}

![Disable SSH password access.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/libreelec_ssh_disable.jpg){.zoom}

## Setup Jellyfin on Kodi

Finally, let's go to the fun part and connect to our Jellyfin server thanks to the [jellyfin-kodi add-on][addon].

[addon]: https://github.com/jellyfin/jellyfin-kodi

I copied the steps here from [the official instructions][addon-official], specifically the [embedded
devices intructions][addon-embedded] the the [install Jellyfin for Kodi
instructions][addon-jellyfin] and adding my screenshots. We will install the Jellyfin for Kodi
add-on, not the JellyCon one as I find the former much better integrated in the UI.

[addon-official]: https://jellyfin.org/docs/general/clients/kodi/
[addon-embedded]: https://jellyfin.org/docs/general/clients/kodi/#embedded-devices-android-tv-firestick-and-other-tv-boxes
[addon-jellyfin]: https://jellyfin.org/docs/general/clients/kodi/#install-jellyfin-for-kodi-add-on

1. Install add-on repository.

![Go to the "File Manager" menu.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/01.jpg){.zoom}

![Click on "Add Source".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/02.jpg){.zoom}

![The popup "Add file source" will appear.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/03.jpg){.zoom}

![Click on the "\<None\>" item.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/04.jpg){.zoom}

![Enter "https://kodi.jellyfin.org" in the text box that appeared, then click on "OK".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/05.jpg){.zoom}

![Give a name to the source, here "Jellyfin Repo".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/06.jpg){.zoom}

Then press OK. Now, we can actually install the add-on.

![Go to the "Add-ons" menu.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/010.jpg){.zoom}

![Click on "Install from zip file".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/011.jpg){.zoom}

![Choose "Jellyfin Repo" or the name you gave to the source earlier.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/012.jpg){.zoom}

![Select "repository.jellyfin.kodi.zip".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/013.jpg){.zoom}

![A popup will appear, choose to authorize unknown sources by clicking on "Settings".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/014.jpg){.zoom}

![Choose "Yes" when the "Warning!" popup appears.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/015.jpg){.zoom}

2. Install the Jellyfin for Kodi add-on.

Alright, now that the Jellyfin repository is installed, we can finally install the Jellyfin add-on!

![Go to the "Add-ons" menu.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/020.jpg){.zoom}

![Choose "Install from repository".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/021.jpg){.zoom}

![Choose "Kodi Jellyfin Addons".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/022.jpg){.zoom}

![Choose "Video add-ons".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/023.jpg){.zoom}

![Pick "Jellyfin", _not_ "JellyCon".](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/024.jpg){.zoom}

![When installed, a check mark will appear.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/025.jpg){.zoom}

After a few seconds, a popup will appear to choose which Jellyfin server to connect to. Assuming one
is discoverable locally, you will see the following.

![Select main server screen.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/030.jpg){.zoom}

![Pick user.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/031.jpg){.zoom}

![Select "Add-on" playback mode.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/032.jpg){.zoom}

![Choose which library to sync by selecting one or multiple libraries on the left.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/033.jpg){.zoom}

![Press "OK" when all libraries you want to sync are selected.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/034.jpg){.zoom}

![After a few seconds, a notification will appear showing progress.](/images/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3/035.jpg){.zoom}

And you're done! You can now use your Jellyfin server on the TV. A few ideas for what to do next:

- Automate Jellyfin/Kodi with Home Assistant. For example, I pause the room speakers when playback
  starts.
- Synchronize pictures to use as screensavers on the TV

Finally, I rebooted just to make sure everything worked as intended.
