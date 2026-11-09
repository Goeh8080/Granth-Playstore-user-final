# Real Granth view examples

These are **actual Flutter GranthApp screenshots**, not generated UI, stock photos or reconstructed miniature icon cards. They are cropped below the page heading only; the genuine grid controls, FolderRow/GranthCard widgets, real app fonts and real cover render remain intact. No debug banner or chooser appears inside them.

Offline regeneration: `CAPTURE_EXAMPLES=1 flutter test test/granth_examples_capture_test.dart --no-pub`. Flutter3.47.7;390×780 logical pixels,2× render, cropped to780×812 pixels. Folder sample uses existing2-column control; flat all-granth view uses the existing3-column (3×3) control, with three actual GranthCard widgets verified on the same row. Grid choice is independent of the mode and remains user/admin-controlled.

Fixed representative data: public app endpoint `https://granth.wnmsolutions.com/api/index.php?request=getGranths`, fetched7Nov2026,14:33 IST.106 records; fixture keeps public book id/title/author/description/cover path/position/count only. Counts/content are examples and may change; they are not live analytics. No account/internal-user metadata is copied.

Source fixture: `test/fixtures/granth_examples/catalog.json`. Real covers were read from the same app's public media host, not from an external asset hunt. Original artwork/book-cover rights remain with their respective rights holders; no new license or authorship of that artwork is claimed. These are contextual screenshots of the owner's app requested for its view chooser. The screenshot graphics use the repository's existing theme/fonts/vector symbols.

The two runtime PNGs total 530323bytes. Lossless RGB PNG optimization retains every rendered pixel; original photo files are not enhanced/recompressed for app display. Cover source files are test fixtures only, not bundled runtime assets.

## Original cover fixture hashes
- `https://granth.wnmsolutions.com/granths/praman_69bbba95277ff.jpg` SHA256 `159ee87215ce5dd26693f378e0109b0d7430100ad1ec7d30b16d01afd133daeb`
- `https://granth.wnmsolutions.com/granths/praman_69bbc71e21216.webp` SHA256 `0374f51dfe07c9ecef85e82ea65b3eaf175e79fa9a660ffb1e02066a9aac513f`
- `https://granth.wnmsolutions.com/granths/praman_6a4bdae79caa5.jpg` SHA256 `cdafc2c103efab3f6d1944457c569afaf1e3af0cc2c1e176f0629640f7c1d01a`

## Side-by-side chooser update (7Nov2026)
Both actual screenshots are shown simultaneously, no chooser scroll. Right screenshot is genuinely rendered with `cols=3`; the selector and actual first-row geometry are asserted, not merely relabeled. User grid preference remains independent and is regression-tested unchanged after choosing flat mode. TiroDevanagariSanskrit-Regular is explicitly loaded during offline capture (alongside other actual bundled font families), preventing test-default Ahem blocks for Latin words/numerals. Source book content is not rewritten to hide glyph issues.

Compact chooser adapts image height/copy, not system text scale. Same-frame visibility and decoded images tested at320dp, text1.0/1.3, plus2.0 at480dp height. Both choices preserve full tap targets/accessible image labels and persisted mode behavior.

## Looping scroll previews + once-only choice (9Nov2026)
The chooser pans each real screenshot strip with a lightweight in-app `AnimationController` (no video package). Controllers dispose when the sheet closes. Reduce-motion / एनिमेशन कम keeps a static top crop. Selection is once-only and final: the user-facing "दृश्य बदलें" control is removed; users who already saved a mode keep it and are never re-prompted. Admin-forced grid layout via remote config is unchanged and still takes precedence over the user's column preference.
