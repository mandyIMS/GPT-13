# Muse Web for older iPhones

An unofficial, Gecko-based Muse web client for older iPhones. It opens
`muse.ai` directly instead of embedding Apple's WebKit, so it remains
usable on systems whose bundled WebKit is too old for the Muse website.

This project is **not affiliated with, endorsed by, or sponsored by Meta**.
Muse is a product of Meta. Do not mistake this client for the official
Muse app.

## Acknowledgements

This project is a focused derivative of
[GPT-13](https://github.com/JKleissJL/GPT-13), which is itself a focused
derivative of
[Reynard Browser](https://github.com/minh-ton/reynard-browser). Reynard
Browser provides the original iOS application structure and Gecko
integration; GPT-13 narrowed that foundation to a single-site client and
added its TrollStore-oriented workflow. This fork keeps that foundation
and retargets it to a single Muse client. Please see the upstream
projects and [NOTICE.md](NOTICE.md) for the full upstream and third-party
acknowledgements.

## Status

This is experimental software for iOS 13 and later. It has not been
tested on a device yet: no Muse release has been built or installed.
The first build is still pending.

It is a single-site client, not a general-purpose browser:

- opens Muse (`muse.ai`) in-app;
- preserves Muse web sign-in and website data;
- opens ordinary external links in the system default browser;
- supports file, photo, camera, microphone and voice permissions requested
  by the Muse page;
- provides a downloads list and a scoped website-data reset;
- includes TrollStore JIT support for Gecko.

## Installation

No release package exists yet. Once a build succeeds, the TrollStore
package will be attached to this repository's Releases page (or to a
GitHub Actions run artifact). Transfer it to the iPhone and install it
with TrollStore.

The first launch can take several seconds while Gecko creates its profile.
This package is intended for TrollStore-capable devices. Do not install it
through a signing service or distribution certificate.

## Important notes

- A normal Muse account is required. This project does not include an API
  key or provide access to any paid plan.
- Sign-in, downloads, upload availability and voice features are supplied
  by the Muse website and can change independently of this project.
- The project deliberately allows Muse and its sign-in/challenge domains in
  the embedded view. User-activated links to other sites are handed to the
  system browser. If Muse sign-in redirects through a domain that is not
  yet allowed, sign-in will fail or open externally until that domain is
  added and the app is rebuilt.
- This is not an official Meta app. Do not report its issues to Meta as
  though it were one.

## Building

The project is developed on macOS with Xcode, Rust, `ldid`, `xcodegen`, and an
Apple Silicon-compatible Gecko toolchain. Clone with submodules:

```bash
git clone --recursive https://github.com/mandyIMS/GPT-13.git
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

Note: the release scripts as written expect the repository on an external
volume under `/Volumes/` and a preinstalled Mozilla toolchain cache. A
fresh GitHub-hosted runner does not provide either. See
`.github/workflows/build-tipa.yml` for the current draft workflow and its
known gaps before expecting a one-click build.

## Development and testing

The focused app code is in `browser/ReynardGPT/`; Gecko UIKit compatibility
changes live in `patches/widget/uikit/`. See
[`docs/ReynardGPT-Device-Test.md`](docs/ReynardGPT-Device-Test.md) for a device
test checklist. That checklist still uses ChatGPT wording from GPT-13;
follow the same steps with `muse.ai` until it is updated. Never share a
Gecko profile, cookies, login tokens, or an app container in a bug report.

## Upstream and licensing

This project is derived from Reynard Browser via GPT-13 and embeds Mozilla
Firefox Gecko through a pinned Git submodule. Upstream credits and
third-party notices are recorded in [NOTICE.md](NOTICE.md).

The project source is GPL-3.0, except the files under `patches/`,
which modify Firefox Gecko and are licensed under MPL-2.0. See
[LICENSE](LICENSE) and [LICENSE.firefox](LICENSE.firefox).
