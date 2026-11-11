---
type: Feature Stories
description: Current acceptance criteria and UX contract for Help and manual feedback in Disk Atlas.
created: "2026-11-12"
---
# Help and feedback

- Help opens useful local documentation without requiring a website or network.
- Help and the bottom-right bug action open the same feedback window on Home and in results.
- A message is required; kind and optional reply email accompany automatic app/macOS versions and allowlisted app diagnostics, visible before Send.
- Manual feedback sends only on Send. Separately, opt-in automatic diagnostics sends bounded operation timings and fixed failure codes; default off. No source paths, crash capture, automatic screenshots or device/user identifiers.
- Empty/oversized messages and invalid nonempty email block sending without deleting text.
- Sending has a Stop action. Network/rate-limit failures retain the draft; success is explicit.
- Closing and reopening retains the draft in memory. No draft is written to disk.
- Both languages/themes and the minimum workspace size remain usable.

UX:
- Flow: Help → Report a bug, or bottom-right bug → message → optional email/screenshot → review technical details → Send → visible confirmation → Close.
- Surface: a small independent window, also reachable while an auxiliary window is open; Escape closes it and retains the draft, Command-Return sends, Return in the editor inserts a newline.
- States: empty form, invalid input, sending with Stop, retryable error with preserved text, success with Write another.
- Words: one set of terms in GLOSSARY.md; Attach uses no ellipsis, per owner preference.
- Access: message receives initial focus; labelled native checkbox, real buttons and editor, visible state beyond color.


## Diagnostics and screenshot

- App/build/macOS versions, active screen, latest operation duration/count/status and fixed error code are shown before sending manual feedback.
- Attach opens the native PNG/JPEG picker; one image is resized, re-encoded without metadata, previewed and removable. Never capture the screen automatically or send the source filename.
- Invalid/large files show an error and retain the text/previous image. Loading and sending have Stop.
- Automatic diagnostics defaults off, is independently controlled in Settings, emits only scan/duplicate timing and fixed errors while on. Switching off cancels in-flight work; no disk queue, no replay of previous events.
- No crash handler, session recording, search strings, folder names, paths, file contents or persistent identity.

UX:
- Flow: bug → text → Attach → native picker → thumbnail → Remove or Send → success. Cancel picker preserves draft.
- Surface: same feedback window; technical details expand inline; automatic diagnostics lives in Settings with a short explicit data description.
- States: no image, loading/Stop, image/Remove, invalid image, network error with retained draft, success clears image. Small windows scroll the form; Send stays visible.
