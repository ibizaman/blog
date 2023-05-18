---
title: Declarative WiFi with Encrypted Secret on NixOS
tags: server, nix
---

This blog post recaps how to install NixOS with only a WiFi connection, how to manage the WiFi
connection declaratively and how to encrypt the passphrase during deploy.

This is only really useful for a machine that will not move much. If you're trying to configure WiFi
on a laptop, I would recommend using `services.networkmanager` and configure the connection
manually.

<!--toc:start-->
- [Why Encrypt the Passphrase](#why-encrypt-the-passphrase)
- [Enable WiFi Manually](#enable-wifi-manually)
- [Initial Install WiFi Configuration](#initial-install-wifi-configuration)
- [Deploy with Encrypted Secret](#deploy-with-encrypted-secret)
<!--toc:end-->

# Why Encrypt the Passphrase

Like for any non-encrypted secret in NixOS, two issues arise if you put the passphrase in clear in
the configuration:

1. the passphrase will be stored in the nix store of both the build machine and the target machine
2. and the passphrase will be stored in the git repo you use to manage your deploy.

The solution to the first issue is to use something like the `deployment.keys` option that is
supported by most [deployment tools](https://nixos.wiki/wiki/Applications#Deployment).

The solution to the second issue is to encrypt the secret in the repo, and decrypt it on the target
machine, after deploy. [Multiple
tools](https://nixos.wiki/wiki/Comparison_of_secret_managing_schemes) exist to handle this.

In this post, we will use [sops-nix](https://github.com/Mic92/sops-nix) which provides a solution
for both issues.

# Enable WiFi Manually

A little aside before we start. If something goes wrong, you can always setup WiFi manually with the
commands from the
[wpa_supplicant](https://wiki.archlinux.org/title/wpa_supplicant#Connecting_with_wpa_passphrase) and
[dhcpcd](https://wiki.archlinux.org/title/Dhcpcd#Configuration) Arch Linux wiki. The only difference
with the wiki is you do not need to install the commands as they come with NixOS.

```bash
sudo wpa_supplicant -B \
     -i wlan0 \
     -c <(wpa_passphrase SSID PASSPHRASE)

touch dhcpcd.conf && \
    sudo dhcpcd --config dhcpcd.conf
```

# Initial Install WiFi Configuration

Assuming you just booted on NixOS for the first time on the target machine and you made some edits
to `configuration.nix`, your next step is to run `nixos-rebuild switch`. But first, you need a
working internet connection.

What is following looks like a convoluted way to set WiFi up but it sets us up nicely to be able to
declaratively set the WiFi connection with an encrypted password later on.

In the machine's `configuration.nix`, add:

```nix
networking.wireless = {
  enable = true;
  environmentFile = "/run/secrets/MY_SSID_PSK";
  networks = {
    "MY_SSID" = {
      psk = "@MY_SSID_PSK@";
    };
  };
};
```

Replace `MY_SSID` with the name of the SSID you will be connecting to.

Then create the file `/run/secrets/MY_SSID_PSK` with the following content:
```
MY_SSID_PSK=theactualpassphrase
```

# Deploy with Encrypted Secret

Like we said earlier, we will use [nix-sops](https://github.com/Mic92/sops-nix) to encrypt the
secret at rest and during deploy.

A few prerequisites:
- You copied over the machine's `configuration.nix` locally which includes the `networking.wireless`
  section we added earlier.
- You created a public/private key pair that allows you to ssh into the target machine.

Now, to actually encrypt the secret, we will follow the [nix-sops readme
file](https://github.com/Mic92/sops-nix). The gist is:

1. Install the necessary packages to run the commands:
   ```bash
   nix shell nixpkgs#ssh-to-age nixpkgs#sops
   ```
   You need the latest `ssh-to-age` binary as the one provided in 21.11 does not have all the
   necessary arguments.

2. Create an `age` secret from that public/private key pair used to connect to the target machine.
   ```bash
   ssh-to-age -private-key \
              -i ~/.ssh/TARGET_HOSTNAME \
              -o ~/.config/sops/age/TARGET_HOSTNAME.txt
   age-keygen -y ~/.config/sops/age/TARGET_HOSTNAME.txt
   ```
   Use the output of that last command for `admin_nixos` later on.

   Also, replace `TARGET_HOSTNAME` with the actual hostname of the target machine.

   If the private key uses a passphrase, you'll first need to export an environment variable with the passphrase:
   ```bash
   read -s SSH_TO_AGE_PASSPHRASE
   export SSH_TO_AGE_PASSPHRASE
   ```

3. Get the `age` secret from the target machine
   ```bash
   ssh-keyscan -t ed25519 TARGET_MACHINE_IP | \
       ssh-to-age
   ```
   Use the output of that command for `server_TARGET_HOSTNAME` later on.

   Note here I am using the IP of the target machine as `ssh-keyscan` was failing to retrieve
   anything with the hostname. I do not know why.

4. Then fill in `.sops.yaml` with:
   ```yaml
   keys:
     - &admin_nixos age1...
     - &server_TARGET_HOSTNAME age1...
   creation_rules:
     - path_regex: secrets/[^/]+\.yaml$
       key_groups:
       - age:
         - *admin_nixos
         - *server_TARGET_HOSTNAME
   ```
   That file should be living in your repository used for deploys.

   A few replacements are needed in the file:
     - Replace `age1...` string for `admin_nixos` with the value we obtained at step 2.
     - Replace `age1...` string for `server_TARGET_HOSTNAME` with the value we obtained at step 3.
     - Replace `TARGET_HOSTNAME` with the actual hostname of the target server.

5. Create the encrypted secret file:
  ```bash
  mkdir -p secrets
  sops secrets/secrets.yaml
  ```
  The content of the file should be the content of the file in `/run/secrets` we created earlier:
  ```
  MY_SSID_PSK=theactualpassphrase
  ```

6. Wire up SOPS in the `configuration.nix`:
  ```nix
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/home/ME/.config/sops/age/TARGET_HOSTNAME.txt";
    secrets."MY_SSID_PSK" = {};
  };
  ```

Now, next time you will deploy, sops will use the secret file, send it over to the target machine
when deploying, decrypt the file and populate the content of `/run/secrets/MY_SSID_PSK`.
