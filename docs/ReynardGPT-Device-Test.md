# ReynardGPT first-device test

Target device: iPhone 13 Pro, iOS 15.3.1, installed through TrollStore.

## Install and first launch

1. On the Mac, run `./tools/release/verify-reynardgpt-tipa.sh` once more and keep its SHA-256 output with the test notes.
2. Copy `dist/ReynardGPT-TrollStore.tipa` to the iPhone with AirDrop, Files, or another local transfer method.
3. In TrollStore, open the `.tipa`, install it, and confirm that the displayed bundle identifier is `com.jkleissjl.gpt13`.
4. Launch ReynardGPT while connected to a normal network. Allow up to 15 seconds for the first Gecko profile and content process to start.
5. Open Settings in ReynardGPT and record the Gecko version and JIT status. JIT should change from “Waiting” to “Enabled (TrollStore ptrace helper)”.

## Functional order

Run these checks in order so a failure can be associated with the smallest possible subsystem.

1. Confirm that launch opens `https://chatgpt.com/` and there is no address bar, tab UI, bookmarks, history, homepage, sidebar, or extension UI.
2. Sign in with the normal ChatGPT web login. Exercise the actual OAuth provider in use and complete any Cloudflare challenge inside ReynardGPT.
3. Confirm that the account shows the expected Plus/Pro plan and can send and receive a normal conversation without an API key.
4. Force-quit ReynardGPT, relaunch it, and confirm that the login and conversation state persist.
5. Reboot the iPhone once, relaunch ReynardGPT, and confirm that the login state still persists.
6. Open another ChatGPT conversation and a ChatGPT internal settings page; both must remain inside ReynardGPT.
7. Tap a normal cited source link. Confirm that the system default browser opens and ReynardGPT does not navigate to that external page.
8. Test a cited source that uses `target=_blank` or `window.open`; it must also open in the default browser.
9. Return to ReynardGPT and test Back, Refresh, Share, and Settings.
10. Attach one file from Files, one image from Photos, and one new camera photo. Confirm each upload reaches ChatGPT.
11. Test microphone/voice access. Confirm both the ReynardGPT permission prompt and the iOS system prompt behave correctly.
12. Download a file produced by ChatGPT and use the presented share sheet to save or open it.
13. Select text in a ChatGPT answer, then test Copy and Select All.
14. In Settings, choose “Clear Login and Website Data”; confirm ChatGPT reloads signed out. Sign in once more to verify the clean-profile path.
15. Leave the app in the background for several minutes, return, and confirm that the single session is still usable or reloads cleanly.

## Logs to collect if launch or Gecko fails

1. Connect the iPhone to the Mac by USB and tap **Trust** on the phone if prompted.
2. Open macOS **Console**, select the iPhone in the sidebar, click Start, and filter for any of:
   - `ReynardGPT`
   - `Reynard Helper`
   - `GeckoRuntime`
   - `[JIT]`
   - `ts_ptrace_jit`
3. Clear the Console view, reproduce the problem once, stop capture, and save the log as a text or logarchive file.
4. In Xcode 15.2, open **Window → Devices and Simulators**, select the iPhone, then open **View Device Logs**. Export the newest crash reports for ReynardGPT and Reynard Helper.
5. Also capture screenshots of the TrollStore app details and ReynardGPT Settings page so the installed bundle identifier and JIT status are visible.
6. Give Codex the saved logs, crash reports, screenshots, exact last successful test step, and whether the failure occurs only on first launch or every launch.

Do not export the Gecko profile, cookies, login tokens, or the app container. The logs above are sufficient for initial diagnosis and avoid exposing ChatGPT authentication data.
