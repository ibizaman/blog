---
title: What's up with Nextcloud webdav slowness?
tags: nextcloud
---

Accessing Nextcloud's web UI, using http, seems reasonably fast but accessing the webdav interface
is painfully slow. Like, it doesn't even seem to work at all slow.

What's up with that?

Let's embark in a journey on how to profile Nextcloud.

## Did anyone stumbled onto this issue already?

Searching for slow Nextcloud webdav brought up [this post](1). It details what the OP tried to fix
their issue but with a not satisfying conclusion. Anyway, they provide very useful curl commands to
test timing:

Http timing:

```bash
time curl \
  -H 'Cookie:$SESSION' \
  'https://$MYINSTANCE/apps/dashboard/#/'
```

`$MYINSTANCE` would for example be `nextcloud.domain.com`, which I'm going to use from now on.

Webdav timing:

```bash
time curl \
  -X 'PROPFIND' \
  -H 'Depth: 1' \
  -u '$USER:$PASSWORD' \
  'https://$MYINSTANCE/remote.php/dav/files/$USER/'
```

I advice instead to leave out the `$PASSWORD` as curl will ask for it. Otherwise, the password will
appear at least in your shell history.

## Try to replicate

I tweaked the above commands by adding the `-I` flag so I could see the headers but not the
response:

```bash
time curl -I ...
```

Http timing is not bad:

```
$ 
real    0m0.464s
user    0m0.086s
sys     0m0.012s
```

Webdav timing is abysmal:

```
real    0m26.931s
user    0m0.095s
sys     0m0.011s
```

## Is the issue in the Nextcloud code or elsewhere?

I need to know first if the issue lies in the Nextcloud php code, in the phpfpm server serving the
php code or in the nginx proxy that's serving Nextcloud publicly.

To know that, I enabled the access log in nginx with the following snippet. The convoluted string
actually produces a valid json format which makes it super easy to investigate.

```nix
services.nginx.logError = "stderr warn";
services.nginx.appendHttpConfig = ''
  log_format apm
    '{'
    '"remote_addr":"$remote_addr",'
    '"remote_user":"$remote_user",'
    '"time_local":"$time_local",'
    '"request":"$request",'
    '"request_length":"$request_length",'
    '"server_name":"$server_name",'
    '"status":"$status",'
    '"bytes_sent":"$bytes_sent",'
    '"body_bytes_sent":"$body_bytes_sent",'
    '"referrer":"$http_referrer",'
    '"user_agent":"$http_user_agent",'
    '"gzip_ration":"$gzip_ratio",'
    '"post":"$request_body",'
    '"upstream_addr":"$upstream_addr",'
    '"upstream_status":"$upstream_status",'
    '"request_time":"$request_time",'
    '"upstream_response_time":"$upstream_response_time",'
    '"upstream_connect_time":"$upstream_connect_time",'
    '"upstream_header_time":"$upstream_header_time"'
    '}';

  access_log syslog:server=unix:/dev/log apm;
  '';
```

Take a look in the [nginx
manual](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#variables) to see what the
`upstream_*` variables mean.

This is what I see for the `curl` request above. I formatted the json output for easier reading.

```json
Sep 17 21:08:45 myserver nginx[287808]: myserver nginx: 
{
  "remote_addr": "$ADDR",
  "remote_user": "$USER",
  "time_local": "17/Sep/2023:21:08:45 +0000",
  "request": "PROPFIND https://nextcloud.domain.com/remote.php/dav/files/$USER/ HTTP/2.0",
  "request_length": "185",
  "server_name": "$INSTANCE",
  "status": "207",
  "bytes_sent": "1401",
  "body_bytes_sent": "633",
  "referrer": "-",
  "user_agent": "curl/8.2.1",
  "gzip_ration": "-",
  "post": "-",
  "upstream_addr": "unix:/run/phpfpm/nextcloud.sock",
  "upstream_status": "207",
  "request_time": "26.058",
  "upstream_response_time": "26.057",
  "upstream_connect_time": "0.000",
  "upstream_header_time": "26.057"
}
```

This indicates the problem lies in the Nextcloud code as the time spent in the "upstream" part is
the same as the total request time.

## Let's profile Nextcloud

We need to enable the xdebug extension and add some lines to the php.ini config. In NixOS, that's done quite easily by adding:

```nix
services.nextcloud = {
  # Disable the minifier and outputs some additional
  # debug information.
  extraOptions = {
    "debug" = true;
    "filelocking.debug" = true;
  };

  # Enable profiling xdebug mode and save file only
  # if the trigger_value is given in the request.
  phpOptions = {
    "xdebug.mode" = "profile";
    "xdebug.trigger_value" = "debug_me";
    "xdebug.output_dir" = "/var/log/xdebug";
    "xdebug.start_with_request" = "trigger";
  };
  
  # Adds xdebug extension
  phpExtraExtensions = all: [ all.xdebug ];
};

# Create output folder with correct permission.
systemd.services.phpfpm-nextcloud.preStart = ''
  mkdir -p /var/log/xdebug
  chown -R nextcloud: /var/log/xdebug
'';
```

This will create a `cachegrind.out.XXXXXX` file under the `/var/log/xdebug` directory for each
request having the cookie `XDEBUG_PROFILE=debug_me` set.

You could leave out the `start_with_request` option but I wouldn't advice doing that as normal usage
of the Nextcloud instance will also produce a lot of `cachegrind.out.XXXXXX` files which are just
noise.

Anyway, the full `curl` request to time webdav becomes:

```bash
time curl -I -s \
  -X 'PROPFIND' \
  -H 'Depth: 1' \
  -u '$USER' \
  --cookie 'XDEBUG_PROFILE=debug_me' \
  'https://$MYINSTANCE/remote.php/dav/files/$USER/'
```

This is the full output of the response:

```bash
Enter host password for user '$USER':
HTTP/2 207 
server: nginx
date: Sun, 17 Sep 2023 21:08:45 GMT
content-type: application/xml; charset=utf-8
x-xdebug-profile-filename: /var/log/xdebug/cachegrind.out.552470
set-cookie: oc_sessionPassphrase=XYZ; path=/; secure; HttpOnly; SameSite=Lax
content-security-policy: default-src 'none';
expires: Thu, 19 Nov 1981 08:52:00 GMT
cache-control: no-store, no-cache, must-revalidate
pragma: no-cache
set-cookie: occXYZ=XYZ; path=/; secure; HttpOnly; SameSite=Lax
set-cookie: cookie_test=test; expires=Sun, 17 Sep 2023 22:08:44 GMT; Max-Age=3600
vary: Brief,Prefer
dav: 1, 3, extended-mkcol, access-control, calendarserver-principal-property-search, nextcloud-checksum-update, nc-calendar-search, nc-enable-birthday-calendar
x-request-id: 9Yjd8BK6bGf92s7qXpWW
x-debug-token: 9Yjd8BK6bGf92s7qXpWW
strict-transport-security: max-age=31536000; includeSubDomains


real    0m28.410s
user    0m0.050s
sys     0m0.007s
```

Again that abysmal execution time. Here, we're interested in the `x-xdebug-profile-filename`
response header which shows us the corresponding profiling file.

I will open that file in KCacheGrind. I downloaded that file on my laptop then started
KCacheGrind with `nix run nixpkgs#kcachegrind`.

Here is what I saw, and my jaw dropped (open image in a new tab to be able to zoom):

<img src="/images/2023-08-12-what's-up-with-nextcloud-webdav-slowness/KCacheGrind-output.png" />

I'm not a KCacheGrind expert but let me give you a primer. Each line shows:

- a function call in the `Function` column,
- how many times that function got called in the `Called` column,
- how long was spent somewhere inside that function and any of its descendants in the `Incl` column,
- and how long was spent somewhere inside that function and _none_ of its descendants in the `Self` column.

Here we can see the overwhelming majority of the time is spent inside 1 call to the `php::usleep`
function which is called once by the `OC\Security\Bruteforce\Throttler->getDelay` function.

All the slowness was thus due to Nextcloud's [bruteforce avoidance
feature](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/bruteforce_configuration.html).
Somehow it thought someone was trying to bruteforce access to the server. But why did it activate at
all as I'm the only user?

## The issue was seemingly unrelated

Looking back in the logs I could see that the `remote_addr` of the request was pointing to my router
instance and not to the user's real IP address.

This was due to my particular network setup. When making a request to my Nextcloud instance at
`nextcloud.domain.com` from inside the same subnet as where the instance is located, my router kicks
in and re-routes the request to the internal subnet. This somehow mangles the origin of the request
and the Nextcloud instance thinks every request comes from the same IP, leading to bruteforce
protection to kick in.

TBH, I have no idea what my router is actually doing but I circumvented by adding
`nextcloud.domain.com` to my internal dns server with:

```nix
services.dnsmasq = {
  extraConfig = ''
    address=/$MYISNTANCE/192.168.1.10
  '';
```

Where `192.168.1.10` is the internal IP of the server hosting Nextcloud.

Now, the webdav request finishes in `8.188s` and the `remote_addr` shows correctly the one from my
laptop. It's still slow and more profiling showed the issue lies now in ldap calls. But I'll leave
that for a later blog post.
