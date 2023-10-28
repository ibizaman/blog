---
title: Migrate Nextcloud User To LDAP Account
tags: 
---

<!--toc:start-->
- [The Issue](#the-issue)
- [Prerequisite](#prerequisite)
- [The CLI Way to Migrate Data](#the-cli-way-to-migrate-data)
- [The Web UI Way to Migrate Data](#the-web-ui-way-to-migrate-data)
- [Conclusion](#conclusion)
<!--toc:end-->

# The Issue

When setting up Nextcloud for the first time, I created some users. Everything was fine.

But then, I wanted to integrate with [LLDAP][1] to manage the users through a LDAP server. The issue
arose from the fact that the user created from Nextcloud is not the same as the one created from the
LDAP server.

This means the new user has none of the data of the old user. We need to migrate data to the new user and then delete the old one.

[1]: https://github.com/lldap/lldap

For example, with a hypothetical user called "bob":

- Created from Nextcloud:
  - Display name: `bob`
  - Username: `bob`
  - Path on the filesystem: `$nextcloud_root/data/bob`
- Created from LLDAP:
  - Display name: `bob`
  - Username: `e7749dfe-9740-440d-b857-0c0c508c6876`
  - Path on the filesystem: `$nextcloud_root/data/e7749dfe-9740-440d-b857-0c0c508c6876`

As you can see, the username ends up being a UUID. For Nextcloud, everything about these two users
is different.

You can see the display name and username of a user by going to the `/settings/users` endpoint.

# Prerequisite

Before continuing on and (spoiler) migrating data from one user to the other, you first need to have
created both users on Nextcloud. I assume the old Nextcloud user was already created, otherwise you
have no reason to read this post. But the new LDAP user is probably not yet created.

To do that, you have to login into Nextcloud with that new LDAP user. Nextcloud is smart enough to
handle having two users with the same display name but two different username like in the example
above.

To connect as the old bob user, just use `bob` and the old password. To connect as the new bob user,
use `bob` and the new password.

# The CLI Way to Migrate Data

CLI transfer ownership is done with the following command:

```bash
occ files:transfer-ownership \
  [options] [--] \
  <source-user> <destination-user>
```

Running `occ files:transfer-ownership --help` tells us:

> All files and folders are moved to another user - outgoing shares and incoming user file shares
> (optionally) are moved as well.

There's a `--move` option but I could never use it successfully. I had assume without setting this option that the folders would be somehow copied but no, they are effectively transferred. Every time I tried to use it, I get the following error:

```bash
Destination path does not exists or is not empty
```

Anyway, with our hypothetical "bob" user, the command becomes:

```bash
occ files:transfer-ownership \
  bob e7749dfe-9740-440d-b857-0c0c508c6876
```

Note the ownership transfer is executed right away.

# The Web UI Way to Migrate Data

Here, we go in the UI to transfer ownership of folders. Later, the nextcloud cron job will take care
of actually moving the folders.

1. In the old account you want to move files from, go to `Settings > Sharing`
2. In the  `Files` section, click on `Choose file or folder to transfer`.
   
   Since I had more than 10 folders to transfer, I tried playing it smart and selecting "no" folder, assuming this would transfer all the folders. But no, although the UI lets you do that, the cron job fails later on.

   The trick here was just to move all folders I wanted to transfer into a new folder and transfer
   that folder.

3. Choose the new owner.
4. Click on "Transfer".
5. Log out then log in with the new user and accept the ownership transfer.
6. Wait for the cron job to kick in.

This schedules the transfer through the nextcloud cron job. So to see if it works, you'll need to
monitor that systemd service. In my case, it failed because the job couldn't access the `perl`
binary. I fixed that by [making it available to the cron job][10].

[10]: https://github.com/ibizaman/selfhostblocks/commit/cb7fb66ee2ce1390846ea2e338a8195c5168c4a2

To avoid waiting for the cron job to kick in on its own, just start it manually with `systemctl start nextcloud-cron.service`.

# Conclusion

Now you can transfer all data from legacy accounts to new LDAP managed accounts using the CLI or the
Web UI. Of course, this can be used to transfer from any user to any user.

Remember to test the transfer by monitoring the nextcloud cron job if you're using the Web UI way.
