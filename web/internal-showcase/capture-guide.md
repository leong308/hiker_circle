# Internal showcase capture guide

Updated 2 October 2026.

The presentation includes 48 features across 10 chapters. Previous media has been detached from this page. Every feature now has a fresh screenshot or recording brief in `catalog.json`, shown directly beside its feature points.

## Capture what each feature asks for

- Screenshot: capture each specified screen and save it with the filename shown.
- Recording: follow the numbered steps, keep the full portrait screen visible, and use the suggested duration. A separate screenshot is unnecessary.
- Use dark mode on the current build. Let photos, maps and forecasts load first.
- Use demo account details. For safety actions, use the specified isolated no-dispatch demo and fictional contacts; for button capture, use explicit test mode.
- The Archive chapter asks for a new capture of the original build, labelled with its build date.
- Send original PNG/JPG screenshots and MP4 recordings, with device, app build, date and a note identifying seeded or staged data.

The complete filename list is in [capture-manifest.md](capture-manifest.md). It contains 29 recordings and 39 screenshots. The same briefs are available feature by feature on the internal page.

## Wiring supplied media

1. Inspect the supplied file against the item's `capturePlan`. Verify its screen, build and demo state.
2. Place accepted originals in `web/internal-showcase/media/` with the listed filenames. Preserve portrait content without cropping.
3. Set the item's `source` to `device` and `image` or `video` to `/internal/app-showcase/media/<filename>`. For additional screenshots, use `images: [{ "src": "/internal/app-showcase/media/<filename>", "alt": "Screen description" }]`.
4. Keep `points` and `capturePlan` intact. Replace `notes` with the device/build/date and any staged-state label.
5. Run `node scripts/validate_internal_showcase.cjs`. Preview chapter navigation, feature points, full-size screenshots and video controls on desktop and mobile before deployment.

Only new device captures stored in this page's media directory are displayed. Shared public-site captures and rendered interface previews remain detached from the internal presentation.

