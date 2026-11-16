# Website preparation

The Firebase Hosting website is maintained in `web/`; `firebase.json` serves
`build/web/`. Public images, historical Evolution media, and shared privacy
assets belong in `web/site-assets/` and `web/privacy-assets/` so a clean checkout
does not depend on files left over in an ignored build directory.

Run from the repository root:

```powershell
node tool/prepare_website.cjs --check --strict
node tool/prepare_website.cjs --strict
```

Preparation copies an explicit allowlist of website files onto `build/web/`, maps
`web/internal-showcase/` to `build/web/internal/app-showcase/`, and preserves
unrelated Flutter output. Only linked showcase images and recordings are copied.
Capture logs, guides, and other source metadata are excluded. Stale files inside
website-owned asset directories are removed, including a legacy source-path
showcase copy. It stops before copying if any displayed local asset is absent or
empty. Check mode does not change output files.

The explicitly approved Foundation image may use `source: "archive"` with
`captureMeta.archive: true`. It is counted separately from fresh device captures
and must stay labelled as a historical reference with its capture date unknown.

The internal showcase keeps unrecorded features visible with their capture
instructions. Only verified media files use `source: "device"`; pending capture
plans are reported separately. Add `--strict-captures` when every requested
capture must be complete before publication. This also checks partially wired
plans, so a supplementary screenshot cannot silently satisfy a requested video.

The live-location map configuration is generated from the public
`MAPBOX_ACCESS_TOKEN` environment variable or the ignored `.env.public` mobile
configuration. Only `pk.` tokens are accepted; no other environment values are
copied. Without a public token, the page retains its existing map fallback.

Preview `build/web/` locally after preparing:

```powershell
node tool/preview_website.cjs --port 4173 --proxy-stats
```

Open the printed localhost URL. The server supports Firebase page aliases,
internal showcase routes, video range requests, and optional read-only fetching
of the public statistics endpoint. Omit `--proxy-stats` for offline QA; live
statistics then show their normal unavailable state. The server binds only to
`127.0.0.1` and serves the prepared output. Stop it with Ctrl+C.

Firebase Hosting publication uses
the existing project and requires the normal CLI account access:

```powershell
firebase deploy --only hosting --project hiker-circle
```

Historical captures retain their original date. Replacing a current screenshot
or recording requires inspecting its UI and recording its device, build, and
capture date in the showcase catalog or capture inventory.
