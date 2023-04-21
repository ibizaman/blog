---
title: Server setup - Introduction
tags: server
---

This is the introductory post in the let's build a server series. This
series goes through all the steps needed to setup the same server I
have at home. Along the way, I'll explain everything I know or thought
of while setting up this server.

We'll build a box with a media server, automated movies and series
downloader protected by VPN, a file server and synchronizer,
integration with dropbox, a code server, dynamic IP support,
monitoring, RSS support, SSO, a dashboard, backup and recovery.

We'll also talk about how your laptop and phone will interact with the
server, so essentially file synchronization, picture viewing and
backup.

![Our dashboard to be](/images/screenshot_keycloak.png)

We will install and configure on an Archlinux box:

- [Bazarr](https://www.bazarr.media/)
- [Borgmatic](https://torsion.org/borgmatic/)
- [Caddy](https://caddyserver.com/)
- [Deluge](https://deluge-torrent.org/) through VPN
- DynDNS through [Godaddy](https://www.godaddy.com/)
- [Ersatztv](https://ersatztv.org/)
- [Gitlab](https://about.gitlab.com/)
- [GnuPG](https://gnupg.org/)
- [Haproxy](http://www.haproxy.org/)
- [Homer](https://github.com/bastienwirtz/homer)
- [Jackett](https://github.com/Jackett/Jackett)
- [Jellyfin](https://jellyfin.org/)
- [Keycloak](https://www.keycloak.org/)
- [LVM](https://sourceware.org/lvm2/)
- [MDADM](http://neil.brown.name/blog/mdadm)
- [Nextcloud](https://nextcloud.com/)
- [Oauth2-Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)
- [OpenVPN](https://openvpn.net/)
- [Password Store](https://www.passwordstore.org/)
- [PostgreSQL](https://www.postgresql.org/)
- [Radarr](https://radarr.video/)
- [Rclone](https://rclone.org/)
- [Redis](https://redis.io/)
- [Sonarr](https://sonarr.tv/)
- [TinyTinyRSS](https://tt-rss.org/)
- [PHP-FPM](https://php-fpm.org/)

You'll notice I left out an automation tool like Docker or Ansible
which we won't use here. The goal of this serie is to empower you and
to make you understand what's going on under the hood. That's how I
like to build the things I use.

I assume you are familiar with the command line, that's about it.

# Hardware and Distro

- CPU: Intel i5 760 2.80GHz, 4 cores
- RAM: 16GB
- Graphics Card: GeForce GTS 250
- Disks:
  - Samsung SSD 950 PRO (256GB)
  - TOSHIBA HDWD110 (1 TB)
  - WDC WD10EZEX-60W (1 TB)
  - ST2000DM006-2DM1 (1.82 TB) x2
- Distro: Archlinux 5.13.13-arch1-1

In short, it's an old desktop repurposed in a server with some new
hard drives. The drives are in a RAID 1 setup so I have a total of
2.82 TB of available storage. The SSD is used to store `/var` to speed
up writing logs and access to PostgreSQL.
