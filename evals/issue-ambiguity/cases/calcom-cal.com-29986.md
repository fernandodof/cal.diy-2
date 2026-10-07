---
id: calcom-cal.com-29986
title: Persistent Booking ID Across Reschedules
link: https://github.com/calcom/cal.diy/issues/29986
human_score: 1
snapshot: 2026-10-07
---

Hi Cal.com Team,

I would also like to suggest another feature related to booking IDs and rescheduling.

At the moment, when a new booking is created, Cal.com provides a UID that we can use in Zapier and other automations. However, when the same booking is rescheduled, a new UID is generated.

This creates an issue in automation workflows because the rescheduled booking can be treated as a completely new booking rather than the same appointment with an updated date and time.

It would be very useful if every booking had a permanent Booking ID that remains unchanged throughout the full lifecycle of the booking.

For example:

Original booking
Booking ID: ABC123
UID: UID001

After rescheduling
Booking ID: ABC123
UID: UID002

The UID could still change if required internally, but the permanent Booking ID would remain the same.

This persistent ID should ideally be available through:

• Zapier triggers and actions
• Webhooks
• API responses
• Booking details
• Rescheduling events

This would make it much easier to identify the original booking, update the correct record in systems such as ClickUp or a CRM, and prevent duplicate projects or tasks being created after a reschedule.

From an automation perspective, the logic would then simply be:

Same Booking ID = update the existing booking record

rather than:

New UID = potentially create a new record

I believe a persistent booking identifier would significantly improve Cal.com integrations and make rescheduling much more reliable for businesses using automated workflows.
