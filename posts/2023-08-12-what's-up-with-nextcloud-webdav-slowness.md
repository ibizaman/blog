---
title: What's up with Nextcloud webdav slowness?
tags: nextcloud
wip: true
---

Accessing Nextcloud's web UI, using http, seems reasonably fast but accessing the webdav interface
is painfully slow. Like, it doesn't even seem to work at all slow.

What's up with that?

# Did anyone stumbled onto this issue already?

Searching for slow Nextcloud webdav brought up [this post](1) which a pretty detailed log of what the OP tried to fix their issue but with an IMO not satisfying conclusion. Anyway, they provide very useful curl commands to test timing:

Http timing:

```bash
time curl 'https://$MYINSTANCE/apps/dashboard/#/' -H 'Cookie:$VALIDCOOKIES'
```

Webdav timing:

```bash
time curl -X PROPFIND -H "Depth: 1" -u $USER:$PASSWORD https://$MYINSTANCE/remote.php/dav/files/$USER/
```

I advice instead to leave out the `$PASSWORD` as curl will ask for it. Otherwise, the password will
appear at least in your shell history.

# Try to replicate

I tweaked the above command to look like this:

```bash
time $(curl -s ... > /dev/null)
```

This way, I wasn't outputting the response at all and only saw the timings. The result is telling:

Http timing is not bad:

```
$ 
real    0m0.464s
user    0m0.086s
sys     0m0.012s
```

Webdav timing is abysmal:

```
real    0m13.931s
user    0m0.095s
sys     0m0.011s
```

# Debug this

First thing first, I enabled access log in the nginx instance serving Nextcloud:

```nix
services.nginx.logError = "stderr warn";
services.nginx.appendHttpConfig = ''
    log_format postdata '$remote_addr - $remote_user [$time_local] '
                        '"$request" <$server_name> $status $body_bytes_sent '
                        '"$http_referer" "$http_user_agent" "$gzip_ratio" '
                        'post:"$request_body"';

    access_log syslog:server=unix:/dev/log postdata;
  '';
```

For Http:

```
Aug 13 03:30:34 baryum nginx[1080156]: baryum nginx: 192.168.50.1 - - [13/Aug/2023:03:30:34 +0000] "GET /apps/dashboard/ HTTP/2.0" <n.tiserbox.com> 200 688806 "-" "curl/8.2
.1" "-" post:"-"
```
