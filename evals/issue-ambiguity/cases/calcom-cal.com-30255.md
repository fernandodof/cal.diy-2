---
id: calcom-cal.com-30255
title: companion: timezone picker has no search across 417 entries
link: https://github.com/calcom/cal.diy/issues/30255
human_score: 2
snapshot: 2026-10-07
---

**Labels:** ✨ feature, 🧹 Improvements, bookings, ui

---

**Problem:**

Picking a timezone in the Companion app means scrolling a single flat list of 417 entries with no way to type and filter. Finding `Europe/Helsinki` on an iPhone takes dozens of flicks past every African and American zone first, and a slip lands on a neighbour like `Europe/Guernsey`.

The iOS picker renders the whole `TIMEZONES` constant as buttons inside one `ContextMenu.Items`, so the native menu is the only affordance. The Android screen does the same in a plain `ScrollView`. Neither has a text input in front of the list.

```tsx
// apps/mobile/components/screens/EditAvailabilityNameScreen.ios.tsx:188
{TIMEZONES.map((tz) => (
  <Button
    key={tz.id}
    systemImage={timezone === tz.id ? "checkmark" : "globe"}
    onPress={() => handleTimezoneSelect(tz.id)}
    label={tz.label}
  />
))}
```

![Timezone picker on iOS: a flat native context menu with no search field](https://raw.githubusercontent.com/Mark-Life/issue-assets/main/calcom/companion-ios-timezone-picker.jpg)

The list itself is fine. Listing `Europe/Helsinki` and `Europe/Sofia` separately even though they share an offset is the right call, because people look for their city. It is the lack of search on top of it that hurts.

Line numbers are against `calcom/companion` at `8ee5b15`.

**Proposed solution:**

Replace the context menu with a sheet that has a search field at the top and filters the list as you type, the way iOS Settings > General > Date & Time does it. Matching on the city part after the slash, ignoring underscores, covers the common case. Pre-selecting the device timezone at the top of the sheet would remove the scroll entirely for most users.

Open question: whether matching should also cover country names and local spellings, such as "Finland" finding `Europe/Helsinki`, or only the label as shown.
