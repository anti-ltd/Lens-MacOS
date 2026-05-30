# Lens Roadmap

Living plan. We knock these out piece by piece; each is meant to ship something
usable on its own.

## Flagship — Lens Studio (cinematic recording for app trailers)

Architecture: **record raw video + an event track, then render the polished
result in a separate pass** (Screen Studio model). Re-editable, smoothest
auto-zoom (full lookahead), unlocks backgrounds / trim / GIF after the fact.
Auto-zoom ships **fully automatic** first; manual keyframes come in S7.

- [x] **S1 — Event capture.** Record raw video + sidecar event track: cursor
      path (per frame), clicks, keystrokes, recorded-region geometry. Writes
      `<name>.lensevents.json` next to the recording.
- [x] **S2 — Render scaffold.** `AVAssetReader → CIImage → AVAssetWriter` with a
      per-frame `transform` hook + progress; audio passes through. Triggered via
      menu → "Render Recording…". Validated headlessly (identity + rescale).
- [x] **S3 — Scene framing.** `SceneCompositor` + `SceneStyle`: background
      (gradient / solid / wallpaper / transparent), inset, rounded window,
      shadow, macOS-window & browser chrome, aspect presets (source / 16:9 /
      1:1 / 9:16 / 4:3). Presets (Clean / Marketing / Window / Browser /
      Vertical) in *Output → Studio frame*; applied by "Render Recording…".
      `frameStill()` gives Track C still-image frames for free.
- [x] **S4 — Auto-zoom camera.** `CameraPlan` + `StudioComposer`: zero-phase
      smoothed virtual camera that punches in on clicks/keystrokes, follows the
      cursor while zoomed, and eases back out after `idleHold`. Toggle + zoom
      amount in *Output → Studio frame*; reads the recording's `events.json`.
- [x] **S5 — Cursor cinema.** `CursorPlan` + `CursorArt`: synthetic enlarged,
      smoothed cursor drawn post-zoom (constant on-screen size), click ripples,
      spotlight dim, hide-when-idle. Controls in *Output → Studio frame*.
      (Motion blur deferred to S8 polish.)
- [x] **S5.5 — Webcam PiP.** `WebcamRecorder` captures `camera.mov` alongside
      the screen; `CameraTrack` lock-step reads it and the composer overlays a
      rounded corner bubble. Toggle / size / corner in *Output → Studio frame*.
- [x] **S6 — Keystroke overlay.** `KeystrokePlan` + `KeystrokeArt`: pressed
      shortcuts render as lower-third keycap chips (⌘C, ⌃⇧4…), shortcuts-only by
      default, with fade. Toggle in *Output → Studio frame*.
- [x] **S7 — Studio editor (single recording).** `StudioDocument` (per-recording
      `studio.json`), `StudioPreviewEngine` (seekable composed preview),
      `StudioEditorView`: live preview + scrub/play, all S3–S6 knobs as live
      controls, trim in/out (renderer rebases the timeline), export MP4 + GIF
      with progress. Open via menu → "Open in Studio Editor…".
      *(Manual auto-zoom keyframes + idle-gap cutting deferred to S8/S9.)*
- [x] **S8 — Studio editor ramp-up (multi-clip).** `StudioProject` /
      `StudioClip` (`.lensproj`), `ProjectRenderer` (Studio-renders each clip and
      concatenates them, scaling mixed sizes to a common canvas), and a
      standalone project window (add / reorder / enable / per-clip edit / export).
      Menu → "New Studio Project" / "Open Studio Project…". *(Sequential single
      track; layered multi-track compositing is S10.)*
- [x] **S9 — Cinematic polish.**
  - [x] Punch/pop zoom easing (`CameraStyle.easing` = smooth/punchy) — snappy
        zoom for energetic edits. Controls in editor + *Output → Studio frame*.
  - [x] Subtle 3D tilt/parallax on the window (`SceneStyle.tilt`, perspective
        lean; "3D tilt" slider in the editor)
  - [x] Intro/outro title cards + logo bug (`TitleCard` + `TitleCardRenderer` +
        `VideoConcatenator`; watermark in `StudioComposer`. "Titles & branding"
        section in editor)
  - [x] Background music + audio ducking (`MusicTrack` + `MusicMixer`: loops
        music to length, ducks under recording audio; "Audio" section in editor)
  - [x] Auto-remove-silence / idle-gap cutting (`SilenceDetector` finds
        keep-intervals from the event track; `SilenceCutter` stitches them.
        "Remove silent gaps" toggle in editor)
  - [x] Typing-aware zoom — `AccessibilityProbe` captures the caret/focused-field
        location on key-down; the camera focuses there (not the mouse) while typing.
- [~] **S10 — Maximize editor usability.** (in progress)
  - [x] Text & image/sticker **layers** on the timeline (`StudioLayer`):
        time range, normalized position, size, opacity, text colour. Composited
        fixed (post-zoom) by `StudioComposer`; "Layers" section in the editor
        with per-layer controls. Live in the preview.
  - [x] Keyframed/animated layer properties — fade in/out + move (`StudioLayer`
        `fadeIn`/`fadeOut`/`endX`/`endY`; controls in the editor).
  - [~] Transitions between clips (cross-dissolve) — `ProjectRenderer.crossDissolve`
        (two-track opacity ramp) + "Crossfade" slider; falls back to a hard cut
        if the GPU video-composition export fails. **Needs real-hardware verify.**
  - [ ] Lighting / colour grade
  - [ ] Deeper multi-track timeline UI

### Captured ideas (slot into S4/S9 later)

- **Typing-aware zoom.** Auto-zoom already triggers on keystrokes; refine it to
  zoom toward where typing is happening (active text area / caret region) and
  hold through a typing burst, like the type-focus zooms you see in app videos.
- **"Punch" zoom / pop effect.** A snappy zoom-easing style (fast hard-ish
  zoom-in pulses, optionally a quick in-out "pop" on each action) for energetic,
  quick-cut edits — vs the current smooth ease. Expose as a zoom *easing* /
  intensity option (Smooth ↔ Punchy) on `CameraStyle`.

## Track B — Editor & capture quick wins

- [ ] Self-timer / delayed capture
- [ ] Crop & trim in the editor
- [ ] Post-capture quick-action bar (Annotate / Copy / Save / Pin / Discard)
- [ ] Magnifier callout (zoom inset)
- [ ] Background removal (lift from FileMaster's image editor)
- [ ] Annotation style presets (colors, widths, dashed, shadows)

## Track C — Still-image framing

- [ ] Device / window / browser frames for screenshots (shares S3's compositor)
- [ ] Batch backdrop + multi-size export across the tray

## Track D — Workflow

- [ ] Persistent, OCR-searchable capture history
- [ ] Shortcuts.app actions + URL scheme + CLI
- [ ] GIF export for stills
