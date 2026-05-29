# Lens

A precise, repeatable screenshot utility for macOS. Lens lives in your menu bar
and does both halves of the job competitors split between them: **fast,
repeatable captures** locked to a ratio or exact pixel size, *and* **deep,
in-depth shots** with annotations, beautiful backdrops, scrolling capture, OCR,
and more.

## Capture modes

- **Area** — drag a rectangle. Ratio-locked live when the active preset pins one.
- **Window** — highlight and click a window; captured tightly via ScreenCaptureKit.
- **Full screen** — the display under the pointer.
- **Scrolling** — auto-scrolls and stitches a long page/chat/document into one image.
- **Color picker** — a magnifier loupe; click copies the hex.

Each mode has its own global hotkey (defaults layer `⌃` on top of the macOS
`⌘⇧3/4/5` set to avoid collisions) and a menu-bar item.

## The repeatable half (beats fixed-frame tools)

Presets pin a **frame constraint** — a locked aspect ratio (`16:9`, `1:1`,
`9:16`…) or **exact output pixels** (`1920×1080`, `1200×630` Open Graph,
`1280×800` Mac App Store). Set one, and every capture comes out matching: the
area overlay locks to the ratio while you drag, window/full-screen grabs are
centre-cropped, and pixel presets resize to the exact size on export. Build your
own presets for docs, social, and ads.

## The in-depth half (beats heavyweight editors)

- **Annotations**: arrow, line, rectangle, ellipse, freehand, text, highlight,
  pixelate, blur, spotlight, redact, and numbered steps.
- **Backgrounds**: solid, gradient, or **transparent** cut-out, with padding,
  rounded corners, and drop shadow — applied per-preset or chosen in the editor.
- **OCR & QR**: pull selectable text (or decode codes) from any capture, on-device
  via Vision.
- **Pin**: float a capture as an always-on-top reference window.
- **Destinations**: open in the editor, save to a folder, copy to the clipboard,
  or pin — with an optional always-copy-to-clipboard.

## Architecture

Layered like the rest of the menu-bar apps in this workspace:

- **LensCore** — pure capture/compose logic (ScreenCaptureKit, Vision, Core
  Image, Core Graphics). No UI; unit-tested.
- **LensUI** — the menu-bar host, settings popover, selection/window/loupe
  overlays, and the annotation editor. Depends on `iUX-MacOS` so every surface
  matches the rest of the suite.
- **Lens** — the executable shell (`@main`, AppDelegate adaptor, arg routing).

## Build

```sh
make build      # swift build -c release
make run        # assemble Lens.app and launch it
make debug      # debug build, run in foreground
make icon       # render AppIcon.icns from the in-app renderer
make test       # run the LensCore unit tests
```

Lens needs two macOS permissions (status + grant buttons live in the **About**
tab):

- **Screen Recording** — to capture any pixels. Triggered on first capture.
- **Accessibility** — for the global hotkeys (the `NSEvent` global key monitor
  only receives events once the process is trusted) and for scrolling capture
  (which posts synthetic scroll events). Prompted on first scrolling capture.

A stable local signing identity (`Lens Dev`, picked up automatically by the
Makefile if present) keeps both grants across rebuilds — without it, every
rebuild re-prompts.

## Marketing media (appstage)

Lens implements the `--appstage <state>` driver protocol, so the workspace's
appstage pipeline can build it, seed demo state in an isolated preferences suite,
render the popover/editor on a clean backdrop, and produce banner/OG/App-Store
frames automatically (`appstage build lens`).

---

© 2026 Anti Limited. Released under the Counter-Limitation License (CLL) v1.2.
See [LICENSE.md](LICENSE.md).
