# GPT-13

An unofficial, Gecko-based ChatGPT web client for older iPhones. It opens
`chatgpt.com` directly instead of embedding Apple's WebKit, so it remains
usable on systems whose bundled WebKit is too old for the ChatGPT website.

This project is **not affiliated with, endorsed by, or sponsored by OpenAI**.
ChatGPT and OpenAI are trademarks of their respective owner.

## Acknowledgements

GPT-13 is a focused derivative of
[Reynard Browser](https://github.com/minh-ton/reynard-browser).  Reynard
Browser provides the original iOS application structure and Gecko integration
on which this project is built; GPT-13 narrows that foundation to a single
ChatGPT client and adds its TrollStore-oriented workflow.  Please see the
upstream project and [NOTICE.md](NOTICE.md) for the full upstream and
third-party acknowledgements.

## Status

GPT-13 is experimental software for iOS 13 and later. The current release is
tested primarily on an iPhone 13 Pro running iOS 15.3.1 with TrollStore.

It is a single-site client, not a general-purpose browser:

- opens ChatGPT in-app;
- preserves ChatGPT web sign-in and website data;
- opens ordinary external links in the system default browser;
- supports file, photo, camera, microphone and voice permissions requested by
  the ChatGPT page;
- provides a downloads list and a scoped website-data reset;
- includes TrollStore JIT support for Gecko.

## Installation

Download `ReynardGPT-TrollStore.tipa` from the project's
[Releases](https://github.com/JKleissJL/GPT-13/releases) page, transfer it to
the iPhone, and install it with TrollStore.

The first launch can take several seconds while Gecko creates its profile.
This package is intended for TrollStore-capable devices. Do not install it
through a signing service or distribution certificate.

## Important notes

- A normal ChatGPT account is required. This project does not include an API
  key or provide access to any paid OpenAI plan.
- Sign-in, downloads, upload availability and voice features are supplied by
  the ChatGPT website and can change independently of this project.
- The project deliberately allows ChatGPT and its sign-in/challenge domains in
  the embedded view. User-activated links to other sites are handed to the
  system browser.
- This is not an official OpenAI app. Do not report its issues to OpenAI as
  though it were one.

## Building

The project is developed on macOS with Xcode, Rust, `ldid`, `xcodegen`, and an
Apple Silicon-compatible Gecko toolchain. Clone with submodules:

```bash
git clone --recursive https://github.com/JKleissJL/GPT-13.git
cd GPT-13
```

Fetch and patch Gecko, then build it:

```bash
tools/development/update-gecko.sh
tools/development/apply-patches.sh
tools/development/build-gecko.sh
```

Create and verify the TrollStore package:

```bash
tools/release/build-reynardgpt.sh
tools/release/create-reynardgpt-tipa.sh
tools/release/verify-reynardgpt-tipa.sh
```

The resulting package is written to
`dist/ReynardGPT-TrollStore.tipa`. Build outputs are intentionally not tracked
in Git; release packages are attached to GitHub Releases instead.

## Development and testing

The focused app code is in `browser/ReynardGPT/`; Gecko UIKit compatibility
changes live in `patches/widget/uikit/`. See
[`docs/ReynardGPT-Device-Test.md`](docs/ReynardGPT-Device-Test.md) for a device
test checklist. Never share a Gecko profile, cookies, login tokens, or an app
container in a bug report.

## Upstream and licensing

GPT-13 is derived from Reynard Browser and embeds Mozilla Firefox Gecko through
a pinned Git submodule. Upstream credits and third-party notices are recorded
in [NOTICE.md](NOTICE.md).

The project source is GPL-3.0, except the files under `patches/`,
which modify Firefox Gecko and are licensed under MPL-2.0. See
[LICENSE](LICENSE) and [LICENSE.firefox](LICENSE.firefox).
