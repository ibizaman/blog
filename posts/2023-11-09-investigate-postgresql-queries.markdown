---
title: Investigate Postgresql Queries
tags: nix, postgres
wip: true
---

Let's dive into investigating some slow queries. I'll take as example some real queries I saw on my
server.

First, let's enable Postgresql's [`auto-explain`][1] and [`pg_stat_statements`][2] extensions. In Nix, we do that with:

```nix
services.postgresql.settings = {
  shared_preload_libraries = lib.concatStringsSep "," [
    "auto_explain"
    "pg_stat_statements"
  ];
};
```

[1]: https://www.postgresql.org/docs/current/auto-explain.html
[2]: https://www.postgresql.org/docs/current/pgstatstatements.html

```
\x
SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC;
```
