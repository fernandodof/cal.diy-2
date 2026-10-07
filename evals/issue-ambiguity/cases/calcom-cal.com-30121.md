---
id: calcom-cal.com-30121
title: CalDAV: cannot add a Purelymail account
link: https://github.com/calcom/cal.diy/issues/30121
human_score: 3
snapshot: 2026-10-07
---

### Issue Summary

Adding a Purelymail CalDAV account fails with "Could not add this caldav account". Purelymail does not return `supported-calendar-component-set` for its calendar collection. `tsdav` 2.0.3 throws on the missing property, and after the upgrade from #29718 the calendar is still dropped because `listCalendars` requires `VEVENT` in `components`.

### Steps to Reproduce

1. Apps > Calendar > CalDav (Beta) > Install
2. URL `https://purelymail.com/webdav/<id>/caldav/`, Purelymail username and password
3. Save

### Actual Results

"Could not add this caldav account"

### Expected Results

The calendar is added. A calendar collection without `supported-calendar-component-set` should be treated as VEVENT-capable.

### Technical details

Cal.eu v6.8.9. Reproduced standalone with tsdav against the same account: 2.0.3 throws `Cannot read properties of undefined (reading '_attributes')` in `fetchCalendars`, 2.3.3 returns the calendar with `components: []`.
