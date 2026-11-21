# Admin media in the user app (consumer side) — v1.0.1+2

The app reads the **public media manifest** (Backend Developer contract, 21 Nov 2026). It adds
**no** config fields: nothing in `config.json` / the structure carries media URLs.

```
GET https://granth.wnmsolutions.com/media/manifest.json
```

* Fetched next to the signed config refresh (at most every 5 min), with `If-None-Match` (ETag);
  `304` keeps the cached copy. The last good body is stored for offline starts.
* Empty lists / no file / network error / malformed JSON → built-in icons and bundled videos.
* Parsing is tolerant: unknown fields are ignored, bad entries skipped, `active: false` skipped.
* Code: `lib/services/media_manifest.dart` (`MediaManifest.I.iconFor`, `.videoFor`),
  `lib/widgets/remote_media.dart` (`RemoteIcon`, `LoopVideo`, `MediaCache`).

## Icons (`icons[]`)

| field | use |
| --- | --- |
| `target` | `folder:<religion/group id>` (e.g. `folder:ved`), `folder:<group>/<sub>` (e.g. `folder:ved/rigved`), `slot:<name>` (e.g. `slot:home_banner`, reserved). `''` = library only → ignored |
| `url` | https, PNG / WebP (JPEG tolerated). Cached on the phone by URL — change `?v=` to replace |
| `mime` | if present must be `image/png` / `image/webp` / `image/jpeg` |
| `updated_at` | one icon per target: the newest wins |

No entry / failed download → the built-in v3 icon (the icon pack is unchanged: 56 keys; unknown
keys → `misc`).

## Videos (`videos[]`)

| field | use |
| --- | --- |
| `placement` | `home` \| `granths` \| `settings` \| `login` \| `splash` \| `dashboard` \| `folder` \| `chooser_folders` \| `chooser_list` |
| `target` | `folder:<id>` (for `folder`) or `null` (general) |
| `provider` | played: `direct`, `firebase_storage`, `r2`. Skipped: `youtube`, `google_drive` |
| `url` | https video file |
| `poster_url` | optional still shown while loading / on reduced motion |
| `loop` | default **false** = play once (muted) and hold the last frame; `true` = loop |
| `position` | order (first playable entry per placement + target is used) |

Behaviour: always muted, mixes with other audio, only downloaded when actually shown, paused
when off-screen / app in background. Animations "कम" (or system reduced motion) → still frame
only. Any load / play error → fallback (below).

### What the app uses in v1.0.1

| placement | where | fallback |
| --- | --- | --- |
| `chooser_folders` | once-only "आप ग्रंथ कैसे देखना चाहेंगे" chooser + Settings → ग्रंथ दृश्य, option **फ़ोल्डर** | bundled lotus (`assets/brand/video/lotus_folders.mp4`, loops) |
| `chooser_list` | same, option **एक सूची** | bundled book (`assets/brand/video/book_list.mp4`, loops) |
| `folder` + `target` | that folder's tile / header picture (priority: video › icon › built-in) | admin icon, then built-in v3 icon |
| `granths` (no target) | small picture in the Granth tab header | normal header icon |

`settings` with an empty target is a general Settings background, **not** a chooser preview
(not shown in v1.0.1). `home`, `login`, `splash`, `dashboard` are parsed but not shown yet —
the splash is unchanged.
