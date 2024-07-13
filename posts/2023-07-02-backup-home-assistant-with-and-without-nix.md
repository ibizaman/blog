---
title: Backup Home-Assistant with and without Nix
tags: nix, server
---

This post will show one way to backup Home Assistant automatically. I'll use Nix to set things up
but I will also show the resulting configuration files so you can follow along even if you do not
use Nix.

The idea is to have home assistant itself create a backup using an automation that is scheduled to
run on a regular basis. Then, you can use whatever method to store that backup in a secure location.

# Backup Automation

Create the following shell command (excerpt from `configuration.nix`):

```yaml
shell_command:
  delete_backups: find /var/lib/hass/backups -type f -delete
```

And create the following automation:

```yaml
alias: Create Backup on Schedule
mode: single
trigger:
- minutes: '5'
  platform: time_pattern
action:
- data: {}
  service: shell_command.delete_backups
- data: {}
  service: backup.create
```

This script will run on the 5th minute of every hour to 1/ delete old backups 2/ create a new backup. The backup will live inside the Home Assistant's `backup/` folder.

In Nix, you would do:

```nix
services.home-assistant = {
  config = {
    "automation manual" = [
      {
        alias = "Create Backup on Schedule";
        trigger = [
          {
            platform = "time_pattern";
            minutes = "5";
          }
        ];
        action = [
          {
            service = "shell_command.delete_backups";
            data = {};
          }
          {
            service = "backup.create";
            data = {};
          }
        ];
        mode = "single";
      }
    ];

    shell_command = {
      delete_backups = "find ${config.services.home-assistant.configDir}/backups -type f -delete";
    };
  };
};
```

Note that I [combine declarative and UI defined automations](https://wiki.nixos.org/wiki/Home_Assistant#Combine_declarative_and_UI_defined_automations).

# Allow backup user to access Home Assistant backup folder

Create a `backup` user and make it member of the Home Assistant group:

```bash
useradd backup --system --groups hass
```

In nix:

```nix
users.groups.hass = {
  members = [ "backup" ];
};
```

Now, we need to ensure the `backup` user has access to the Home Assistant folder by enabling the "read" and "execute" group bits. First, by editing the Home Assistant service config and updating the UMask settings:

```bash
systemctl edit home-assistant.service
```

Then enter:

```bash
UMask=0027
```

Finally, restart the service.

In nix:

```nix
users.users.hass.homeMode = "0750";

systemd.services.home-assistant.serviceConfig = {
  UMask = lib.mkForce "0027";
};
```

Second, you need to update the files already created by Home Assistant:

```bash
sudo find /var/lib/hass -type d -exec chmod -r g+rx '{}' ';'
sudo find /var/lib/hass -type f -exec chmod -r g+r '{}' ';'
```
