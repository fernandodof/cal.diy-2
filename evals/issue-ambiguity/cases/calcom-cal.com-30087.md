---
id: calcom-cal.com-30087
title: cal.com get started button look laggy when reload webpage
link: https://github.com/calcom/cal.diy/issues/30087
human_score: 1
snapshot: 2026-10-07
---

### Is your proposal related to a problem?

When reloading the Cal.com homepage, the **Get started** button in the top navigation bar exhibits a visual flash / layout delay (FOUC or hydration lag). While the page is loading, the button appears unstyled or misaligned with a delay before the black background, rounded border, and icon snap into place, making the initial page load feel stuttery and unpolished.

### Describe the solution you'd like

* Ensure critical CSS and base styles for the navbar CTA button are pre-rendered server-side (SSR) to prevent client-side layout shift / style flash during hydration.
* Match the fallback/initial SSR state of the button with its hydrated state so the transition is imperceptible upon refresh.

### Describe alternatives you've considered

* Keeping client-side hydration styling as-is, which leads to layout shift and a jarring visual glitch on slower network connections or cold loads.

### Additional context

* Visible on initial load and hard reloads (`Cmd+Shift+R` / `Ctrl+F5`) across major desktop browsers.
* Affects the top-right header section (`Sign in` / `Get started >`).

### Requirement/Document

* See the attached screen recording/GIF illustrating the button render lag on page refresh.

https://github.com/user-attachments/assets/a2db2091-b054-43e6-9bc7-e0d432e38b21
