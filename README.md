# Slide Notes — iPad & Mac

**Take handwritten notes directly on the slides of any presentation video, even when the
slides were never published. One keyboard shortcut is all it takes.**

### Why

Conference talks, lectures and tech presentations on YouTube almost never come with
downloadable slides. If you want to take notes on top of them, you're left pausing the video,
taking screenshots, cropping them and importing them into a notes app, one slide at a time.
Over a talk with tens or even hundreds of slides, that quickly becomes too tedious to keep up.

Slide Notes removes all of that. You mark the part of the screen where the presentation is shown
**once**. From then on, pressing a **single shortcut** while you watch captures exactly that area
and puts it on your iPad as a new page, ready to write on with the Apple Pencil. There's nothing
to crop, save or import, and you never have to leave the video.

It's made for:

- **Videos without public slides**, such as conference talks on YouTube, recorded lectures and
  webinars.
- **People who want to write directly on the slides** with little to no effort, instead of
  keeping notes in a separate document.

### What it is

Slide Notes is two apps that work together:

- **Slide Notes for Mac** (macOS) takes a screenshot of a region of the screen you choose,
  typically the slide area of a video player, but also a video call or a live presentation. You
  trigger it with one button or a system-wide keyboard shortcut (**⇧`** by default) without
  leaving the video.
- **Slide Notes for iPad** (iPadOS) is a notebook for the Apple Pencil. Every screenshot from
  the Mac shows up right away as a new page at the end of the open note. You annotate it, and you
  can export the whole note as a PDF.

The apps talk to each other directly over Apple's Multipeer Connectivity (the technology behind
AirDrop). There's no server, no IP address to enter and no shared Wi-Fi network needed.

<p align="center">
  <img src="docs/images/mac-capture.png" alt="Slide Notes for Mac next to a lecture video in the browser: the red frame marks the selected capture region around the slide, and the Screenshot button with the ⇧` shortcut sends it to the iPad" width="900">
  <br>
  <em>Slide Notes for Mac (left) with the capture region outlined on a lecture video (right).
  Press <b>Screenshot</b> or <b>⇧`</b> to send the framed slide to the iPad.</em>
</p>

<p align="center">
  <img src="docs/images/ipad-note.png" alt="The same Agents slide on the iPad as a new page, annotated in blue handwriting with the Apple Pencil; the toolbar shows pen, highlighter, eraser, colors, widths and smoothing, and a notice reads New slide added as page 1 with a Show button" width="900">
  <br>
  <em>…and a moment later it's a new page on the iPad, ready to annotate with the Apple Pencil.</em>
</p>

> **Status:** proof of concept. Both apps are built with Flutter; platform features (screen
> capture, global hotkey, peer-to-peer link, Apple Pencil double-tap) are implemented natively
> in Swift.

> **Local only — you need both a Mac and an iPad.** Slide Notes currently works only
> between a Mac and an iPad that are physically near each other, connected directly over
> Multipeer Connectivity. There is no cloud sync, web version or remote access, and neither app
> is useful on its own: the Mac app has nowhere to send slides without the iPad, and the iPad
> app only receives slides from the Mac app. Both apps are built from source (they are not on
> the App Store).

---

## Contents

- [How it works](#how-it-works)
- [Features](#features)
- [Complete feature list](#complete-feature-list)
- [Requirements](#requirements)
- [Building & installing](#building--installing)
- [Usage](#usage)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Data storage](#data-storage)
- [Testing](#testing)
- [Permissions & privacy](#permissions--privacy)
- [Known limitations](#known-limitations)

---

## How it works

```
┌──────────────── Mac ────────────────┐                      ┌──────────────── iPad ───────────────┐
│  Slide Notes for Mac            │                      │  Slide Notes for iPad           │
│                                     │   Multipeer          │                                     │
│  1. Pick a screen region (once)     │   Connectivity       │  4. Slide is appended as the last   │
│  2. Press Screenshot or ⇧`          │   (encrypted,        │     page of the open note           │
│  3. PNG is queued and sent ─────────┼──────────────────────┼──▶  — your scroll position doesn't  │
│                                     │   peer-to-peer       │     change                          │
│                                     │   Wi-Fi / Bluetooth) │  5. Annotate with the Apple Pencil  │
│                                     │                      │  6. Export the note as a PDF        │
└─────────────────────────────────────┘                      └─────────────────────────────────────┘
```

1. In the Mac app you choose the part of the screen to capture once. It is remembered and works
   on any connected display.
2. Each time you press **Screenshot** or the shortcut, that region is captured at full Retina
   resolution.
3. The slide is pushed to the iPad that has a note open. If no iPad is connected, slides wait in
   a queue and are delivered in order once one connects.
4. The iPad adds the slide as a new page at the end of the note. **It never moves your view**:
   if you are annotating page 3, you stay on page 3, and a small notification offers to jump to
   the new slide.
