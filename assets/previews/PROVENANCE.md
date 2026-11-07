# Real Granth view examples

These are **actual Flutter GranthApp screenshots**, not generated UI, stock photos or reconstructed miniature icon cards. They are cropped below the page heading only; the genuine grid controls, FolderRow/GranthCard widgets, real app fonts and real cover render remain intact. No debug banner or chooser appears inside them.

Offline regeneration: `CAPTURE_EXAMPLES=1 flutter test test/granth_examples_capture_test.dart --no-pub`. Flutter3.47.7;390×780 logical pixels,2× render, cropped to780×812 pixels. Folder sample uses existing2-column control; flat list uses existing1-column control. Grid choice is independent of the mode and remains user/admin-controlled.

Fixed representative data: public app endpoint `https://granth.wnmsolutions.com/api/index.php?request=getGranths`, fetched7Nov2026,14:33 IST.106 records; fixture keeps public book id/title/author/description/cover path/position/count only. Counts/content are examples and may change; they are not live analytics. No account/internal-user metadata is copied.

Source fixture: `test/fixtures/granth_examples/catalog.json`. Real covers were read from the same app's public media host, not from an external asset hunt. Original artwork/book-cover rights remain with their respective rights holders; no new license or authorship of that artwork is claimed. These are contextual screenshots of the owner's app requested for its view chooser. The screenshot graphics use the repository's existing theme/fonts/vector symbols.

The two runtime PNGs total about572KiB. Lossless RGB PNG optimization retains every rendered pixel; original photo files are not enhanced/recompressed for app display. Cover source files are test fixtures only, not bundled runtime assets.

## Original cover fixture hashes
- `https://granth.wnmsolutions.com/granths/praman_69bbba95277ff.jpg` SHA256 `159ee87215ce5dd26693f378e0109b0d7430100ad1ec7d30b16d01afd133daeb`
- `https://granth.wnmsolutions.com/granths/praman_69bbc71e21216.webp` SHA256 `0374f51dfe07c9ecef85e82ea65b3eaf175e79fa9a660ffb1e02066a9aac513f`
- `https://granth.wnmsolutions.com/granths/praman_6a4bdae79caa5.jpg` SHA256 `cdafc2c103efab3f6d1944457c569afaf1e3af0cc2c1e176f0629640f7c1d01a`
