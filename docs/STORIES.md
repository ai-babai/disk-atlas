---
type: Feature Stories
description: Current acceptance criteria and UX contract for Help and manual feedback in Disk Atlas.
created: "2026-11-12"
---
# Help and feedback

- Help opens useful local documentation without requiring a website or network.
- Help and the bottom-right bug action open the same feedback window on Home and in results.
- A message is required; kind, optional reply email and opt-in version/macOS details are visible before Send.
- Only Send makes a network request to Sentry. No analytics, crash reporting, automatic attachments or source paths.
- Empty/oversized messages and invalid nonempty email block sending without deleting text.
- Sending has a Stop action. Network/rate-limit failures retain the draft; success is explicit.
- Closing and reopening retains the draft in memory. No draft is written to disk.
- Both languages/themes and the minimum workspace size remain usable.

UX:
- Flow: Help → Report a bug, or bottom-right bug → message → optional email/details → Send → visible confirmation → Close.
- Surface: a small independent window, also reachable while an auxiliary window is open; Escape closes it and retains the draft, Command-Return sends, Return in the editor inserts a newline.
- States: empty form, invalid input, sending with Stop, retryable error with preserved text, success with Write another.
- Words: one set of terms in GLOSSARY.md; menu items that ask for input end with an ellipsis.
- Access: message receives initial focus; labelled native checkbox, real buttons and editor, visible state beyond color.
