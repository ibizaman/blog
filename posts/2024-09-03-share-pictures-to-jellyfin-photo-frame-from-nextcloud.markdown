---
title: Display Pictures from Nextcloud to a Kodi Photo Frame
tags: nix, nextcloud, systemd, iot, server
---

So I wanted to show family pictures on the TV.
My current setup is:

- a server using [NixOS][] to host [Nextcloud][],
- an [OrangePi 3][OrangePi] with [Libreelec][] and [Kodi][],
- and mobile phones with the iOS Nextcloud app.

What I wanted is to be able to select, from Nextcloud, which pictures to show on the TV and those would appear there automatically. This post goes over how I did it.

Btw, I'm hosting [Jellyfin][] and using the [Jellyfin For Kodi][] plugin on the OrangePi but this does not matter for the following setup.

[NixOS]: https://nixos.org/
[Kodi]: https://kodi.tv/
[Nextcloud]: https://nextcloud.com/
[Jellyfin]: https://jellyfin.org/
[OrangePi]: https://www.amazon.com/Orange-Pi-Allwinner-Computer-Support/dp/B09TQZH4GJ
[Libreelec]: https://libreelec.tv/
[Jellyfin For Kodi]: https://jellyfin.org/docs/general/clients/kodi/

<!-- ![image example](/images/2023-09-30-share-pictures-to-jellyfin-photo-frame-from-nextcloud) -->

## Wanted User Experience

To show pictures:

1. Pictures are uploaded from the iOS app to Nextcloud.
2. User goes over pictures and shares good ones with the Photoframe Nextcloud user.
3. Wait for screensaver on OrangePi box to start and see new pictures!

To remove pictures:

1. Unshare pictures with Photoframe Nextcloud user.

## Setup

I didn't want the OrangePi to connect to the Nextcloud server using WebDav.
I tried that first and got into scenarios where I was sharing so many pictures
that the screensaver could not load them correctly.
There are multiple reasons for this and one can search to optimize them.
But this got me thinking, why couldn't I instead copy all the shared pictures
to the OrangePi directly?
This makes the solution very robust to any networking mishap.
And that's what I did.

### On Nextcloud

1. I created a `Photoframe` user in Nextcloud.
   I logged in with that user once and configured it to [automatically accept incoming shares][].
2. With my user, I shared some pictures with that new user to test that I could and that the `Photoframe` user would see them.

[automatically accept incoming shares]: https://docs.nextcloud.com/server/latest/user_manual/en/files/sharing.html#internal-shares-with-users-and-groups

### On the Server

The idea here is to `rsync` the shared pictures to the OrangePi box.
This implies that:

- `rsync` has access to the shared pictures only.
- `rsync` can ssh into the OrangePi box.
- `rsync` is installed on the server and the OrangePi box.

To make rsync access the shared pictures only, I mounted the `Photoframe` Nextcloud folder through WebDav in a directory on the server.
This is done using [this Self Host Blocks module][SHB davfs] and with the following config on my server:

```nix
shb.davfs.mounts = [
  # Mount a WebDav folder in the /srv/photoframe.
  {
    remoteUrl = "https://$MYDOMAIN/remote.php/dav/files/photoframe";
    mountPoint = "/srv/photoframe";
    username = "photoframe";
    passwordFile = config.sops.secrets."photoframe".path;
    uid = 992;
    gid = 991;
  }
];
# Password for Photoframe user.
# For now, it must be in format:
#
#   <mountPoint> <username> <password>
#
# In this example, it is:
#
#   /srv/photoframe photoframe XHsbaf...
#
sops.secrets."webdav/nextcloud" = {
  sopsFile = ./secrets.yaml;
  mode = "0600";
  path = "/etc/davfs2/secrets";
};
users.groups.photoframe = {
  # Must correspond to the gid above.
  gid = 991;
};
users.users.photoframe = {
  isSystemUser = true;
  # Must correspond to the uid above.
  uid = 992;
  group = "photoframe";
  home = "/var/lib/photoframe";
  createHome = true;
  packages = [
    pkgs.rsync
  ];
};
```

I could verify this worked by making sure the secret looked good with `cat /etc/davfs2/secrets`
and also by seeing that the `/srv/photoframe` directory was created and not empty. In case of error, check `systemctl status srv-photoframe.mount`.

To be able to ssh into Kodi, I needed to create an ssh key pair.
So I ran the following and got two files `ssh-orangepi` and `ssh-orangepi.pub`:

```bash
ssh-keygen -t ed25519 -N "" -f ssh-orangepi
```

I wrote the private key in my Sops config.
I copied over the public key into the OrangePi's `/root/.ssh/authorizedKeys` file.
I sshed once from the server to the OrangePi to accept the host key fingerprint.
Finally, I could put a cron job that would run `rsync` on a schedule:

[SHB davfs]: https://github.com/ibizaman/selfhostblocks/blob/main/modules/blocks/davfs.nix

```nix
systemd.services.sync-to-orangepi = {
  description = "Sync Pictures to OrangePi";
  after = [ "network.target" "srv-photoframe.mount" ];
  bindsTo = [ "srv-photoframe.mount" ];
  path = [ pkgs.openssh ];
  serviceConfig = {
    User = "photoframe";
    Group = "photoframe";
    Type = "oneshot";
    ExecStart = ''
      ${pkgs.rsync}/bin/rsync \
        --rsh 'ssh -i /etc/davfs2/ssh-salon' \
        # Add more things to exclude if needed.
        --exclude='lost+found' \
        --delete \
        --delete-excluded \
        -a \
        /srv/photoframe/ \
        root@orangepi.$MYDOMAIN:/storage/pictures
      '';
  };
};
# The private ssh key.
sops.secrets."webdav/ssh-orangepi" = {
  sopsFile = ./secrets.yaml;
  mode = "0600";
  owner = "photoframe";
  path = "/etc/davfs2/ssh-salon";
};
systemd.timers.sync-to-orangepi = {
  wantedBy = [ "timers.target" ];
  timerConfig.OnBootSec = "10m";
  timerConfig.OnUnitActiveSec = "2h";
  timerConfig.RandomizedDelaySec = "10m";
};
```

It is important to put `--delete` and `--delete-excluded` in the rsync config.
This way, unsharing pictures will effectively delete them from the OrangePi.

The [BindsTo][] option is important too because it deactivates the service if the WebDav mount point gets stopped.
Otherwise, in that case `rsync` will happily synchronize an empty directory - the unmounted directory - and delete all pictures on the OrangePi.

I checked for any issues with `systemctl status sync-to-orangepi.service`, `systemctl status sync-to-orangepi.timer` and `journalctl -u sync-to-orangepi.service -f`.
Btw, before this steps worked, I needed to install `rsync` on the OrangePi. See next step.

[BindsTo]:  https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#BindsTo=

The files get stored in `/storage/pictures` on the OrangePi, which is on the internal eMMC flash memory.

### On the OrangePi

I first needed to install `rsync`.
For that, I installed the `Network Tools` addon in Kodi.

I then navigated to the Settings menu, chose Interface and went to the Screensaver menu.
There, I said to display pictures from the `/storage/pictures` folder and that was it!

I then tested the screensaver and saw the pictures I shared earlier to test. 

## Possible Improvements

All the manual steps here were tedious and error-prone.
Coming from the NixOS world, I want this all to be declarative.
This means creating users in Nextcloud declaratively and settings user options.
On the OrangePi side, that will mean probably switching from LibreElec to NixOS, but I'm not sure if that's necessary.
Anyway, I'll be working on this.

## Further Reading

I talk about how to setup the OrangePi 3 box with LibreElec and Kodi with the Jellyfin for Kodi plugin in [another blog post][orangepi blog post].

[orangepi blog post]: ./posts/2024-03-22-jellyfin-streaming-media-center-with-libre-elec-and-orange-pi-3.html

I use [Self Host Blocks][SHB] to setup my server with NixOS and [Skarabox][] to bootstrap a new server.

[SHB]: https://github.com/ibizaman/selfhostblocks
[Skarabox]: https://github.com/ibizaman/skarabox
