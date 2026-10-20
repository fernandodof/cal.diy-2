---
id: calcom-cal.com-29950
title: UI: "Refer and earn" settings page has a jarring bounce/jank on load
link: https://github.com/calcom/cal.diy/issues/29950
human_score: 1
snapshot: 2026-10-07
---

### Issue Summary
The "Refer and earn" settings page (Settings → [username] → Refer and earn) has a jarring visual bounce/layout shift when it loads. Instead of rendering smoothly, the page content appears to jump or shift right after load, giving the impression of janky/broken UI rendering rather than a clean transition.

### Steps to Reproduce
1. Log into cal.com
2. Go to Settings
3. Click on your profile name in the sidebar to expand it
4. Click "Refer and earn"
5. Observe the page as it loads

### Actual Results
- The page content visibly bounces/shifts as it renders, instead of appearing smoothly. It looks like a layout shift or unintended animation glitch.

### Expected Results
- The page should load and render smoothly without any visible jump, bounce, or layout shift.

### Technical details
- Browser: Google Chrome is 151
- OS: Windows

### Evidence
Tested manually by navigating to the Refer and earn settings page and observing the bounce on load. Screenshot attached showing the page state.

<img width="2253" height="1350" alt="Image" src="https://github.com/user-attachments/assets/9d36ec81-2373-44a1-90a1-2f17dd1c0aba" />

https://github.com/user-attachments/assets/4d0b80bf-8876-4cc2-a965-b7f3b3447012
