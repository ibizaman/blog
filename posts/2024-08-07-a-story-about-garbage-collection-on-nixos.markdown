---
title: A Story about Garbage Collection on NixOS
tags: nix
---

<!--toc:start-->
- [Context](#context)
- [Starting Small](#starting-small)
- [Going Deeper](#going-deeper)
- [Analyzing Store Size](#analyzing-store-size)
- [Analyzing Store Size Some More](#analyzing-store-size-some-more)
- [Let's step back](#lets-step-back)
<!--toc:end-->

## Context

So you want to cleanup the Nix store.
I wanted too.
This led me down a medium sized rabbit whole.
Read this post to follow it too!
You might learn a couple things.

I realized my disk was close to full.
74Gb available from a 1Tb SAD.
Time to clean up the Nix store!

## Starting Small

The ubiquitous command to delete old NixOS profiles is `nix-collect-garbage`.
So I used just that:

```bash
$ df -h /
Filesystem             Size  Used Avail Use% Mounted on
/dev/disk/by-uuid/...  909G  789G   74G  92% /

$ nix-collect-garbage --delete-older-than 2d --dry-run
removing old generations of profile /home/ibizaman/.local/state/nix/profiles/home-manager
would remove profile version 77
would remove profile version 76
would remove profile version 75
would remove profile version 74
would remove profile version 73
would remove profile version 72
would remove profile version 71
would remove profile version 70
would remove profile version 69
removing old generations of profile /nix/var/nix/profiles/per-user/ibizaman/profile
removing old generations of profile /nix/var/nix/profiles/per-user/ibizaman/profile


$ nix-collect-garbage --delete-older-than 2d
note: currently hard linking saves 22381.91 MiB
16721 store paths deleted, 22869.11 MiB freed

$ df -h /
Filesystem             Size  Used Avail Use% Mounted on
/dev/disk/by-uuid/...  909G  765G   97G  89% /
```

Not bad, but my disk is still quite full.

## Going Deeper

Next step is to understand what Nix GC root exists, their size and determine which one I'm okay to delete and garbage collect.

From [the wiki][wiki], one can print the GC roots with:

```bash
$ nix-store --gc --print-roots | egrep -v "^(/nix/var|/run/\w+-system|\{memory|/proc)"
```

[wiki]: https://wiki.nixos.org/wiki/Cleaning_the_nix_store

This command ignores some paths, notably ones that are used by the current system.

This gave me quite a few GC roots.
Instead of listing them here, I'll break them down into categories

First, the project result directories. For example:

```bash
/home/ibizaman/Projects/selfhostblocks/result-modules
  -> /nix/store/v8va9mzlwnyplgzdjv0n4hy82m6dr9di-nix-flake-tests-success
```

If you don't need to retain those and you're okay to rebuild them later, just delete the link.

```bash
$ rm /home/ibizaman/Projects/selfhostblocks/result-modules
```

I had also some home-manager GC roots like:

```bash
/home/ibizaman/.local/state/home-manager/gcroots/current-home
  -> /nix/store/srp7f0jfjr8bq4vf030cw1jmgh2yqz34-home-manager-generation
```

Understanding why they're needed is done with `nix-store -q --root`:

```bash
$ nix-store -q --roots /nix/store/srp7f0jfjr8bq4vf030cw1jmgh2yqz34-home-manager-generation
/nix/var/nix/profiles/system-145-link -> /nix/store/9fj82c87fphb6j6cxd9i0ns6wiag9gyh-nixos-system-laspin-24.05pre-git
/nix/var/nix/profiles/system-144-link -> /nix/store/yczj1ln41syk95krrw6n26m6c1wy8q3r-nixos-system-laspin-24.05pre-git
/nix/var/nix/profiles/system-147-link -> /nix/store/gyldgm273sgjb214f99h0ks3dbga2qd0-nixos-system-laspin-24.05pre-git
/run/current-system -> /nix/store/gyldgm273sgjb214f99h0ks3dbga2qd0-nixos-system-laspin-24.05pre-git
/nix/var/nix/profiles/system-146-link -> /nix/store/zj4p4fkyjam69ndgydkl8rrl3m09qyrw-nixos-system-laspin-24.05pre-git
/run/booted-system -> /nix/store/zj4p4fkyjam69ndgydkl8rrl3m09qyrw-nixos-system-laspin-24.05pre-git
/home/ibizaman/.local/state/home-manager/gcroots/current-home -> /nix/store/srp7f0jfjr8bq4vf030cw1jmgh2yqz34-home-manager-generation
/home/ibizaman/.local/state/nix/profiles/home-manager-78-link -> /nix/store/srp7f0jfjr8bq4vf030cw1jmgh2yqz34-home-manager-generation
```

This one is clearly used by a lot of stuff, I probably won't be able to clean it up.
It makes sense, it's the `current-home` one after all.
Another one is easier to delete:

```bash
/home/ibizaman/.local/state/nix/profiles/home-manager-77-link
  -> /nix/store/aawzc42n09xg5vm9n3phzagl95b6zfhg-home-manager-generation

$ nix-store -q --roots /nix/store/aawzc42n09xg5vm9n3phzagl95b6zfhg-home-manager-generation
/home/ibizaman/.local/state/nix/profiles/home-manager-67-link
  -> /nix/store/aawzc42n09xg5vm9n3phzagl95b6zfhg-home-manager-generation
```

We also have the direnv related ones:

```bash
/home/ibizaman/Projects/oxo/.direnv/flake-profile-1-link
  -> /nix/store/8b6kd8lcq5vckq0dkpab9hr558088q45-nix-shell-env

$ nix-store -q --roots /nix/store/8b6kd8lcq5vckq0dkpab9hr558088q45-nix-shell-env
/home/ibizaman/Projects/oxo/.direnv/flake-profile-1-link
  -> /nix/store/8b6kd8lcq5vckq0dkpab9hr558088q45-nix-shell-env
```

Same story as the project ones, you can delete them if they're not needed anymore.

And then, I had a bunch of:

```bash
{temp:2597292} -> /nix/store/3d62w5jhcjgdjay4wg351d1jl7l2j2yh-gmp-6.2.1.tar.bz2.drv
```

This means a currently running process is holding on to this path.
If nothing else holds on to the path, stopping the process will allow it to get garbage collected.
Let's check it:

```bash
$ nix-store -q --roots /nix/store/3d62w5jhcjgdjay4wg351d1jl7l2j2yh-gmp-6.2.1.tar.bz2.drv
/home/ibizaman/Projects/blog/result -> /nix/store/ikvnbi9w7ikbwv7501v9hj4ghnc01y9i-site
/home/ibizaman/Projects/blog/.direnv/flake-profile-6-link -> /nix/store/sn3wz8n8md5y31w2505557ylb2ygillk-site-env-env
```

No luck here.
The path is also held by two links.

## Analyzing Store Size

I used a pretty crude method _(output formatted by myself)_:

```bash
$ sudo ncdu /nix/store

[...]
1.6 GiB  /lp2w7k4x4fsaidm18xgqjp2b70i6w6ci-ghc-9.6.4
1.6 GiB  /gjng6wrl7dsk8d98yjfiz9qb3g64h9f2-ghc-9.6.4
1.6 GiB  /2qqlva2zbkdhbyrz4qyacgq57s8kfy1l-ghc-9.4.8
1.6 GiB  /k033yvpca1r7fi0hwgkh5wnky5iixvlk-ghc-9.4.8
1.6 GiB  /psds2pz1qhlr4z8qcahqii6kq1xsawb8-ghc-9.4.8
1.6 GiB  /dpc4240h48a4kmgj684w1wkjmmi8ccxq-ghc-9.2.8
[...]
```

I probably don't need all those GHC version.
Let's see.

```bash
$ nix-store -q --roots /nix/store/dpc4240h48a4kmgj684w1wkjmmi8ccxq-ghc-9.2.8
/home/ibizaman/Projects/blog/result -> /nix/store/ikvnbi9w7ikbwv7501v9hj4ghnc01y9i-site
/home/ibizaman/Projects/blog/.direnv/flake-profile-6-link -> /nix/store/sn3wz8n8md5y31w2505557ylb2ygillk-site-env-env

$ nix-store -q --roots /nix/store/psds2pz1qhlr4z8qcahqii6kq1xsawb8-ghc-9.4.8
/tmp/tmpbldxg_9z/ahsdpqwigcr399x602z9hlyrbmp3pa4q-vm-test-run-postgresql-peerAuth.drv -> /nix/store/ahsdpqwigcr399x602z9hlyrbmp3pa4q-vm-test-run-postgresql-peerAuth.drv
/tmp/tmpbldxg_9z/i00k3m9h6f0ihijmklfk1lhg4dr3cjw7-vm-test-run-postgresql-peerWithoutUser.drv -> /nix/store/i00k3m9h6f0ihijmklfk1lhg4dr3cjw7-vm-test-run-postgresql-peerWithoutUser.drv
/tmp/tmpbldxg_9z/8jc6kjg3qryhzrkggnw3f5kp8xsgzis2-vm-test-run-postgresql-tcpIpWithoutPasswordAuth.drv -> /nix/store/8jc6kjg3qryhzrkggnw3f5kp8xsgzis2-vm-test-run-postgresql-tcpIpWithou>
/tmp/tmpbldxg_9z/mgy2s5368srbps5bdan8774xdf2q1p3f-vm-test-run-monitoring-basic.drv -> /nix/store/mgy2s5368srbps5bdan8774xdf2q1p3f-vm-test-run-monitoring-basic.drv
/home/ibizaman/Projects/blog/.direnv/flake-profile-6-link -> /nix/store/sn3wz8n8md5y31w2505557ylb2ygillk-site-env-env
/tmp/tmpbldxg_9z/la2qw92yhz2y2kd6qv2wn9jjvcy286z0-vm-test-run-postgresql-tcpIPPasswordAuth.drv -> /nix/store/la2qw92yhz2y2kd6qv2wn9jjvcy286z0-vm-test-run-postgresql-tcpIPPasswordAuth.>
/tmp/tmpbldxg_9z/4blarcmd0hrggpvz8qbmkxmgnndmy9ss-vm-test-run-ldap-auth.drv -> /nix/store/4blarcmd0hrggpvz8qbmkxmgnndmy9ss-vm-test-run-ldap-auth.drv
```

I want to keep the GC roots of my blog here, so I won't mess with those.

```bash
$ nix-store -q --roots /nix/store/k033yvpca1r7fi0hwgkh5wnky5iixvlk-ghc-9.4.8
/home/ibizaman/Projects/selfhostblocks/result-vm_authelia_basic -> /nix/store/xrihrmahqg32xwd7f7gjpcj02kpdjp67-vm-test-run-authelia-basic
```

This one can go away.

```bash
$ rm /home/ibizaman/Projects/selfhostblocks/result-vm_authelia_basic
```

```bash
$ nix-store --gc --print-dead
finding garbage collector roots...
removing stale link from '/nix/var/nix/gcroots/auto/44wr5bc9szn0f870qy673kqi8ivhmc7c' to '/home/ibizaman/Projects/selfhostblocks/result-vm_authelia_basic'
determining live/dead paths...
[...]
```

That printed a bunch of paths, good!

```bash
$ nix-store --gc
[...]
note: currently hard linking saves 17869.65 MiB
5011 store paths deleted, 3609.95 MiB freed
```

3Gb saved. Not bad.
Let's try another GHC one.

```bash
$ nix-store -q --roots /nix/store/2qqlva2zbkdhbyrz4qyacgq57s8kfy1l-ghc-9.4.8
/home/ibizaman/Projects/selfhostblocks/result-vm_monitoring_auth -> /nix/store/avqv7a5sr382f35z4ahksa8kilbn569g-vm-test-run-monitoring-basic
/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_peerWithoutUser -> /nix/store/6qgznnl4wmg32q96lmcmwqsvzsxrw1q4-vm-test-run-postgresql-peerWithoutUser
/home/ibizaman/Projects/selfhostblocks/result-vm_ssl_test -> /nix/store/x8vprjx1jfbqzis874sc38b6kx5rmqa1-vm-test-run-ssl-test
/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_tcpIPPasswordAuth -> /nix/store/vrs0klwdk7dxqbagbv3qbxwiv9zh5aly-vm-test-run-postgresql-tcpIPPasswordAuth
/home/ibizaman/Projects/selfhostblocks/result-vm_lib_template -> /nix/store/rgbqh4qmkkdml7inrs564w5r8wj35is4-vm-test-run-lib-template
/home/ibizaman/Projects/selfhostblocks/result-vm_nextcloud_basic -> /nix/store/a783xnwswwh8wmnvb9y2axm4cczcmn98-vm-test-run-nextcloud-basic
/home/ibizaman/Projects/selfhostblocks/result-vm_ldap_auth -> /nix/store/swnzf8lsqq8s60g5mcqaxjd1jz8p2z7m-vm-test-run-ldap-auth
/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_peerAuth -> /nix/store/f935av428f1cky6s8mh4yvf36y0m5g9a-vm-test-run-postgresql-peerAuth
/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_tcpIPWithoutPasswordAuth -> /nix/store/6nmzajhcrh8vgd65ck5hawy9bwq0c6z3-vm-test-run-postgresql-tcpIpWithoutPasswordAuth
```

Okay, I'm fine getting rid of this one.
With some bash tricks, I can remove all those `result-vm-*` links with a one-liner:

```bash
$ nix-store -q --roots /nix/store/2qqlva2zbkdhbyrz4qyacgq57s8kfy1l-ghc-9.4.8 \
    | awk -F' -> ' '{print $1}' \
    | xargs rm

$ nix-store --gc --print-dead
finding garbage collector roots...
removing stale link from '/nix/var/nix/gcroots/auto/8df9bml2011d32bilfkga61r332q7kik' to '/home/ibizaman/Projects/selfhostblocks/result-vm_lib_template'
removing stale link from '/nix/var/nix/gcroots/auto/l57ixd12ad2kqh7241bg5i7g05vssxr4' to '/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_peerWithoutUser'
removing stale link from '/nix/var/nix/gcroots/auto/c2ja40qlc5110bd000ws1f14drjbkpvk' to '/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_tcpIPWithoutPasswordAuth'
removing stale link from '/nix/var/nix/gcroots/auto/wkm7xcfg9in3c8pm01zl3d5p72p13f9h' to '/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_tcpIPPasswordAuth'
removing stale link from '/nix/var/nix/gcroots/auto/ax33alfd9hw7xigb20qrpncmgmgn32rp' to '/home/ibizaman/Projects/selfhostblocks/result-vm_postgresql_peerAuth'
removing stale link from '/nix/var/nix/gcroots/auto/6i84xyjq0fq6w45nmrr1bmkr26ji02qj' to '/home/ibizaman/Projects/selfhostblocks/result-vm_ldap_auth'
removing stale link from '/nix/var/nix/gcroots/auto/2dp2ac8vqclzci3mab7pc1xj1k67frvw' to '/home/ibizaman/Projects/selfhostblocks/result-vm_ssl_test'
removing stale link from '/nix/var/nix/gcroots/auto/71r3b6wrbg9vayigzgakq4bpsc0j0s5m' to '/home/ibizaman/Projects/selfhostblocks/result-vm_nextcloud_basic'
removing stale link from '/nix/var/nix/gcroots/auto/qc7czk9rq88iflpry9a8zmjvfrcjsq2s' to '/home/ibizaman/Projects/selfhostblocks/result-vm_monitoring_auth'
determining live/dead paths...

$ nix-store --gc
[...]
note: currently hard linking saves 14657.84 MiB
6299 store paths deleted, 7420.39 MiB freed
```

Let's see where we're at:

```bash
$ df -h /
Filesystem             Size  Used Avail Use% Mounted on
/dev/disk/by-uuid/...  909G  754G  109G  88% /
```

I continued removing some GHC roots and got up to 120Gb availability.

## Analyzing Store Size Some More

I used some pretty crude commands to figure out what roots take space.

```bash
$ nix-store --gc --print-roots | grep -v "^/proc"
/home/ibizaman/.cache/nix/flake-registry.json -> /nix/store/5bs7lbd1fk22w7bzdd8d6fvysnyzgw35-flake-registry.json
/home/ibizaman/.local/state/home-manager/gcroots/current-home -> /nix/store/srp7f0jfjr8bq4vf030cw1jmgh2yqz34-home-manager-generation
/home/ibizaman/Projects/blog/.direnv/flake-profile-6-link -> /nix/store/sn3wz8n8md5y31w2505557ylb2ygillk-site-env-env
/home/ibizaman/Projects/blog/result -> /nix/store/ikvnbi9w7ikbwv7501v9hj4ghnc01y9i-site
/home/ibizaman/Projects/esp/.direnv/flake-profile-2-link -> /nix/store/ldbk3nd4hpkj9xiryhjy83inl5yawa9z-nix-shell-env
/home/ibizaman/Projects/nix-config/result -> /nix/store/6dbvmllgim249w566fikwxy6yza37i7g-nixos-24.05.20240421.6143fc5-x86_64-linux.iso

$ du -sch $(nix-store --gc --print-roots | grep -v "^/proc" | awk -F ' -> ' '{ print $2 }')
8.0K    /nix/store/5bs7lbd1fk22w7bzdd8d6fvysnyzgw35-flake-registry.json
40K     /nix/store/srp7f0jfjr8bq4vf030cw1jmgh2yqz34-home-manager-generation
68K     /nix/store/pvxnmywrjn7l3rw35zwd87ixd10lkicj-nix-shell-env
13M     /nix/store/ikvnbi9w7ikbwv7501v9hj4ghnc01y9i-site
80K     /nix/store/ldbk3nd4hpkj9xiryhjy83inl5yawa9z-nix-shell-env
1002M   /nix/store/6dbvmllgim249w566fikwxy6yza37i7g-nixos-24.05.20240421.6143fc5-x86_64-linux.iso
```

That last one can go away!

```bash
$ rm /home/ibizaman/Projects/nix-config/result

$ nix-store --gc
finding garbage collector roots...
removing stale link from '/nix/var/nix/gcroots/auto/8xisdidbngs2s2y8y5hizxpvhydns4df' to '/home/ibizaman/Projects/nix-config/result'
deleting garbage...
[...]
deleting unused links...
note: currently hard linking saves 8562.92 MiB
389 store paths deleted, 1128.68 MiB freed

$ df -h /
Filesystem             Size  Used Avail Use% Mounted on
/dev/disk/by-uuid/...  909G  741G  122G  86% /
```

Still 741G used?

## Let's step back

I'm not likely to make any progress cleaning up the Nix store anymore.
So what's clogging up the disk space?

```bash
$ du -hs /nix/store/
75G     /nix/store/
```

Not the nix store, that's for sure.

I ran `ncdu` on my `/home` directory and found roughly 150Gb of usage there.
That doesn't explain the used 741Gb.
Where does that live?

Well, after searching here and there, I found it.
It was the trash!
So obvious in hindsight but I never cleaned the KDE trash.
500Gb was living in there.

Lesson: I should've taken a step back earlier.
On the other hand, this blog post wouldn't exist if I did.
