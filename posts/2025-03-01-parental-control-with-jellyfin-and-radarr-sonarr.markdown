---
title: Parental Control with Jellyfin and Radarr/Sonarr
tags: jellyfin
---

The goal is to create a user in Jellyfin
that can only see media files that
have a given tag, say "kids",
and that tag was set inside Radarr, Sonarr
or another *arr application.

## *arr Configuration

1. Within Settings > Metadata > Kodi,
   check "Enable" and "Movie Metadata".

2. Then, when adding or editing a movie,
   add a tag to mark media that children can watch,
   like "enfants".

   ![Edit modal showing tag used for parental control](/images/2025-03-01-parental-control-with-jellyfin-and-radarr-sonarr/edit_tag.png){.zoom}

This will create a .nfo file that includes the tag:

```xml
<movie>
  ...
  <tag>enfants</tag>
  ...
</movie>
```

If you add this tag to an existing movie
that is already synced with Jellyfin,
click the "Refresh & Scan" button.

## Jellyfin Configuration

In Jellyfin, under Administration > Dashboard > Users,
create a user and in "Parental Control" tab,
only allow items with the tag chosen above:

![Jellyfin option to allow only media with given tag](/images/2025-03-01-parental-control-with-jellyfin-and-radarr-sonarr/allow_tag.png){.zoom}

The tag seems to be case-insensitive.

That's it!
