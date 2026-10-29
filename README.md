# AudioBatch: Batch Process Adobe Podcast Enhance Speech on macOS

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

A small native macOS app that lets you **bulk enhance audio with Adobe Podcast (Enhance Speech)** on the free plan.

The free version only accepts one file at a time, so you normally have to sit there uploading, waiting and downloading file after file. AudioBatch does that loop for you: pick a folder of recordings, pick an output folder, press **Start**, and it uploads each file in turn, waits for Adobe to finish, downloads the enhanced result and moves on to the next one.

> **Not affiliated with Adobe.** "Adobe" and "Adobe Podcast" are trademarks of Adobe Inc. This is an independent, unofficial tool. See [Disclaimer](#disclaimer).

## Features

- Batch / bulk processing of a whole folder of audio or video files
- Adobe Podcast loads inside the app window, so you log in with your own Adobe account
- Saves results as `originalname_enhanced.ext` in the output folder, never overwriting existing files
- Skips files that already have an enhanced output, so you can stop and resume any time
- Retries the upload up to 3 times per file, reloading the page between attempts
- Stops waiting early when the page shows a limit or "too long" message, and lists the failed files at the end
- Live log at the bottom of the window
- Supports `mp3`, `wav`, `m4a`, `flac`, `aac`, `ogg`, `mp4`, `mov`, `aiff`
- One Swift file, no dependencies
- Universal app for Apple Silicon and Intel Macs, downloadable as a `.dmg`

## Requirements

- macOS 12 or newer (Apple Silicon or Intel)
- An Adobe account (a free one works)

## Install

### Download (recommended)

1. Go to the [latest release](https://github.com/pasinduPrabhath/BatchProcessAdobePodcast/releases/latest) and download `AudioBatch-x.y.z.dmg`.
2. Open the `.dmg` and drag **AudioBatch** into the **Applications** folder.
3. Open AudioBatch from Applications.

#### "AudioBatch can't be opened" / "Apple could not verify…"

The app is not notarized by Apple (that requires a paid developer account), so macOS blocks it the first time. To allow it once:

- **macOS 15 and newer:** open the app, click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the AudioBatch message, and confirm.
- **macOS 12 to 14:** right-click (or Control-click) AudioBatch in Applications, choose **Open**, then click **Open** again.

Or run this once in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/AudioBatch.app
```

After that it opens normally. If you would rather not trust a downloaded binary, build it yourself from source (below); it is a single Swift file you can read first.

### Build from source

Needs Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/pasinduPrabhath/BatchProcessAdobePodcast.git
cd BatchProcessAdobePodcast
bash build.sh
```

`build.sh` compiles `App.swift` into `AudioBatch.app` and opens it. You can also double-click `build.command` in Finder to rebuild and relaunch the app. Because you build it yourself, macOS Gatekeeper will not block it.

### Making a release (maintainers)

`package.sh` builds a universal (Apple Silicon + Intel) app and packs it into `dist/AudioBatch-<version>.dmg`:

```bash
bash package.sh 1.0.0
```

To publish it on GitHub, push a version tag. The [Release workflow](.github/workflows/release.yml) builds the `.dmg` on a macOS runner and attaches it to a new GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Usage

1. Open AudioBatch. Adobe Podcast Enhance opens in the window.
2. Log in with your Adobe email and password. "Continue with Google" often does not work inside embedded browsers, so use email login if it fails.
3. Click **Input folder…** and choose the folder with your recordings.
4. Click **Output folder…** and choose where results should go.
5. Click **Start**. Use **Stop** to finish the current step and halt.

Try it on two short files first to make sure everything works on your machine before you start a big batch.

## How it works

AudioBatch wraps `https://podcast.adobe.com/enhance` in a `WKWebView`. For each file it:

1. Reloads the page.
2. Clicks the page's **Choose files** button. The app answers the native file chooser with the file.
3. Waits for processing, then clicks **Download**.
4. Saves the download into the output folder as `name_enhanced.ext`.

It does what you would do by hand, one file at a time. It does not bypass Adobe's limits or call any private API.

Your password is typed into Adobe's own page. The app never reads, stores or sends credentials; the login session is kept by macOS WebKit like in any browser.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| `Upload not possible. Buttons on page: …` | You are probably logged out or on a different page. Log in, press **Reload page**, start again. Open an issue with the button list from the log if it keeps happening. |
| File fails with a limit message | The free plan has limits on file length, size and daily usage. The file is listed as failed; try again later or split the file. |
| Download never starts | Adobe may have changed its page. Open an issue with the log output. |
| Google login does not work | Use email and password login. |

## Limitations

- It finds buttons by their visible text. If Adobe redesigns the page, the matching may need updating.
- The free plan's own limits still apply.
- Only tested on a small number of files so far.

## Disclaimer

This project is provided as is, for personal use with your own account and your own files. Automating a website may be restricted by that site's terms, so please read Adobe's Terms of Use and use this tool responsibly. You are responsible for how you use it.

## License

[MIT](LICENSE)

## Keywords

Adobe Podcast batch, Adobe Podcast bulk upload, Adobe Podcast Enhance Speech batch processing, enhance speech free plan, batch audio enhancement macOS, podcast audio cleanup, noise removal automation, Swift WKWebView automation.
