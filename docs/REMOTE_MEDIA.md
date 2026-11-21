# Remote media (t421) — admin-uploaded folder icons / videos

All fields are **optional and additive**. A missing, empty, unknown or invalid value changes
nothing: the app keeps the painted v3 icon pack and the bundled chooser videos. Older apps ignore
the new keys.

## URL rules (app side, `parseMediaUrl`)

* `https://` only, max 800 characters, a real host.
* The URL **path** must end in an allowed extension (a `?query` is fine):
  * images: `.png` `.webp` `.jpg` `.jpeg` `.svg`
  * videos: `.mp4` (H.264, muted is fine — the app always plays muted)
* Recommended sizes: icon image 256–512 px square, ≤ 200 KB; icon video 240–360 px square,
  H.264, ≤ 600 KB, 3–15 s loop; chooser / brand video 360 px square, ≤ 600 KB. Hard limit
  per file: 12 MB (bigger downloads are dropped).
* A changed file needs a **new URL** (e.g. add `?v=2`): the app caches each URL on disk
  forever (`<app support>/remote_media/`) so it works offline.

## Signed config JSON (`config.json`)

### Per folder: `structure.religions[]`, `.groups[]`, `.groups[].subgroups[]`, `structure.other`

```json
{
  "structure": {
    "religions": [
      {
        "id": "hindu", "title": "हिन्दू", "icon": "om",
        "icon_url": "https://<host>/media/hindu.webp",
        "icon_video_url": "https://<host>/media/hindu.mp4",
        "groups": [
          { "id": "ved", "title": "वेद", "icon": "scroll",
            "icon_url": "https://<host>/media/ved.png" },
          { "id": "puran", "title": "पुराण", "icon": "book-green",
            "icon_video_url": "https://<host>/media/puran.mp4",
            "subgroups": [ { "id": "shiv", "title": "शिव पुराण", "icon_url": "https://<host>/media/shiv.svg" } ] }
        ]
      }
    ],
    "other": { "title": "अन्य", "icon_url": "https://<host>/media/other.png" }
  }
}
```

| field | type | meaning |
|---|---|---|
| `icon_url` | string (image URL) | picture shown instead of the painted `icon` |
| `icon_video_url` | string (mp4 URL) | muted looping video shown instead of the picture/icon |

Priority on a tile: `icon_video_url` › `icon_url` › painted `icon`. The painted icon (or the
picture) is shown while the file loads, offline before the first download, or on any error.
Videos play only while the tile is on screen (paused when scrolled away, in another tab, under
another page or with the app in the background); at most 8 play at once. The existing `icon`
key stays required-as-before (keep sending it: it is the fallback).

### `ui` keys

```json
{
  "ui": {
    "chooser_video_folders": "https://<host>/media/chooser_folders.mp4",
    "chooser_video_list": "https://<host>/media/chooser_list.mp4",
    "brand_video_url": "https://<host>/media/brand.mp4"
  }
}
```

| key | default when missing | where |
|---|---|---|
| `ui.chooser_video_folders` | bundled lotus loop (`assets/brand/video/lotus_folders.mp4`) | once-only "आप ग्रंथ कैसे देखना चाहेंगे" chooser + Settings → ग्रंथ दृश्य, option **फ़ोल्डर** |
| `ui.chooser_video_list` | bundled book loop (`assets/brand/video/book_list.mp4`) | same, option **एक सूची / सभी ग्रंथ** |
| `ui.brand_video_url` | nothing (normal header icon) | small looping logo in the Granth tab header (root) |

`ui.granth_view_mode` (`folders` / `list`) still forces the view: the chooser is skipped and the
Settings videos are shown greyed out (no tap).

## Backend Developer checklist (admin panel)

1. Upload field per religion / group / sub-group / अन्य: "Icon image" (png/webp/jpg/svg) and
   "Icon video" (mp4) → store the file (R2 / public bucket, https) → write its URL into
   `icon_url` / `icon_video_url` of that node in the structure.
2. Three upload fields under UI: chooser folders video, chooser list video, brand video →
   `ui.chooser_video_folders`, `ui.chooser_video_list`, `ui.brand_video_url`.
3. A "remove" button = delete the key (the app falls back to the painted icon / bundled video).
4. Re-upload = new file name or `?v=<n>` (the app caches by URL).
5. Re-sign and publish the config as usual (Ed25519); no other change is needed.
