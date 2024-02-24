---
title: Mounting Webdav Folder in NixOS
tags: nix, nextcloud
---

I want [Digikam][digikam_home] to access Nextcloud storage using WebDav. But Digikam needs this folder to be
actually mounted on the filesystem, so the setup implies some fiddling.

# Internet Search

Here are all the interesting links that helped me figure out how this should work.

From the [Digikam manual][digikam_manual]:

> Collections on Network Shares: these are root album folders stored remote file systems as Samba or
> NFS and mounted as native on your system.

Clearly, this means the folder must be mounted.

Searching on mounting a webdav folder on linux poped up the [Archlinux wiki][archlinux_wiki] on
`davfs2`, giving me one new keyword to search for.

In the [NixOS options search][nixos_option], there is already a `davfs2` service, which is
implemented [here][davfs2_module] and sets up a configuration file, user and (`un`)`mount.davfs2`
programs. Perfect!

A last search returned the [Nextcloud manual][nextcloud_manual] which shows how to manage the davfs2 secrets. This
is not handled by the NixOS options above.

[digikam_home]: https://www.digikam.org
[digikam_manual]: https://docs.digikam.org/en/setup_application/collections_settings.html#setup-root-album-folders
[archlinux_wiki]: https://wiki.archlinux.org/title/Davfs2
[nixos_option]: https://search.nixos.org/options?channel=23.05&size=50&sort=relevance&type=packages&query=davfs2
[davfs2_module]: https://github.com/NixOS/nixpkgs/blob/nixos-23.05/nixos/modules/services/network-filesystems/davfs2.nix
[nextcloud_manual]: https://docs.nextcloud.com/server/20/user_manual/en/files/access_webdav.html#creating-webdav-mounts-on-the-linux-command-line

# Let's try the existing service

On my NixOS machine, I just added the following line and deployed.

```nix
services.davfs2.enable = true;
```

Let's see what we gained:

```bash
$ mount.davfs --help
Usage:
    mount.davfs -V,--version   : print version string
    mount.davfs -h,--help      : print this message

To mount a WebDAV-resource don't call mount.davfs directly, but use
`mount' instead.
    mount <mountpoint>  : or
    mount <server-url>  : mount the WebDAV-resource as specified in
                          /etc/fstab.
    mount -t davfs <server-url> <mountpoint> [-o options]
                        : mount the WebDAV-resource <server-url>
                          on mountpoint <mountpoint>. Only root
                          is allowed to do this. options is a
                          comma separated list of options.

Recognised options:
    conf=        : absolute path of user configuration file
    uid=         : owner of the filesystem (username or numeric id)
    gid=         : group of the filesystem (group name or numeric id)
    file_mode=   : default file mode (octal)
    dir_mode=    : default directory mode (octal)
    ro           : mount read-only
    rw           : mount read-write
    [no]exec     : (don't) allow execution of binaries
    [no]suid     : (don't) allow suid and sgid bits to take effect
    [no]grpid    : new files (don't) get the group id of the directory
                   in which they are created.
    [no]_netdev  : (no) network connection needed
```

The exact command I tried that works with Nextcloud is:

```bash
$ sudo mount \
      -t davfs \
      -o uid=1000 \
      https://$fqdn/remote.php/dav/files/$myuser \
      mnt

Please enter the username to authenticate with server
https://$fqdn/remote.php/dav/files/$myuser or hit enter for none.
  Username: $username
Please enter the password to authenticate user timi with server
https://$fqdn/remote.php/dav/files/$myuser or hit enter for none.
  Password: $password
warning: the server does not support locks
```

I just needed to enter my Nextcloud username and password when prompted.

# Create a secret file

I highly recommend creating an App password for mounting the webdav folder, this is much faster than
using your main account password as can be seen in [this benchmark][benchmark].

[benchmark]: https://github.com/nextcloud/server/issues/32729#issuecomment-1556667151

`davfs2` reads secrets from a file called `/etc/davfs2/secrets`. Using `sops-nix`, you can create
this file with:

```nix
sops.secrets."webdav/nextcloud" = {
  sopsFile = ./secrets.yaml;
  mode = "0600";
  path = "/etc/davfs2/secrets";
};
```

The secret in the sops file must follow a specific format, one line per webdav folder to mount.

```
<what> <user> <password>
```

From our example above, we would have something like this:

```
https://$fqdn/remote.php/dav/files/$myuser $username $password
```

# Make a Systemd service out of it

```bash
systemd.mounts = [
  {
    enable = true;
    description = "Webdav mount point";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  
    what = "https://$fqdn/remote.php/dav/files/$myuser";
    where = "/mnt/nextcloud";
    options = uid=1000,gid=1000,file_mode=0664,dir_mode=2775
    type = "davfs";
    mountConfig.TimeoutSec = 15;
  }
];
```
