---
title: Mounting Webdav Folder in NixOS
tags: nix
wip: true
---

Context is I want [Digikam](1) to access Nextcloud storage using WebDav. But Digikam needs this
folder to be actually mounted on the filesystem, so the setup implies some fstab fiddling.

[1]: https://www.digikam.org

# Internet Search

Here are all the interesting links that helped me figure out how this should work.

From the [Digikam manual](2):
> Collections on Network Shares: these are root album folders stored remote file systems as Samba or NFS and mounted as native on your system.

Clearly, this means the folder must be mounted.

Searching on mounting a webdav folder on linux poped up the [Archlinux wiki](3) on `davfs2`, giving me one new keyword to search for.

In the [NixOS options search](4), there is already a `davfs2` service, which is implemented [here](5) which sets up a configuration file, user and (un)mount.davfs2 programs. Perfect!

A last search returned the [Nextcloud manual](6) which shows how to manage the davfs2 secrets. This is not handled by the NixOS options above.

[2]: https://docs.digikam.org/en/setup_application/collections_settings.html#setup-root-album-folders
[3]: https://wiki.archlinux.org/title/Davfs2
[4]: https://search.nixos.org/options?channel=23.05&size=50&sort=relevance&type=packages&query=davfs2
[5]: https://github.com/NixOS/nixpkgs/blob/nixos-23.05/nixos/modules/services/network-filesystems/davfs2.nix
[6]: https://docs.nextcloud.com/server/20/user_manual/en/files/access_webdav.html#creating-webdav-mounts-on-the-linux-command-line

# Let's try the existing service

On my NixOS config, I just added the following line and deployed.

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
$ sudo mount -t davfs \
      https://$fqdn/remote.php/dav/files/$myuser mnt -o uid=1000
Please enter the username to authenticate with server
https://$fqdn/remote.php/dav/files/$myuser or hit enter for none.
  Username: $username
Please enter the password to authenticate user timi with server
https://$fqdn/remote.php/dav/files/$myuser or hit enter for none.
  Password: $password
warning: the server does not support locks
```
