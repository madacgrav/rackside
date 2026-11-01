# Task: Series edit/cancel and shared calendar event update/removal (GitHub #7, BACKLOG row 5)

Recurring session series are created in bulk and share one recurring calendar event, but
the app cannot edit series occurrences, and cancelling or deleting a series occurrence
skips calendar cleanup (`SessionRunViewModel.setStatus`/`delete` gate on
`seriesId == nil`), leaving stale calendar entries. Add a way to edit and cancel/delete a
single occurrence or the series going forward, keeping the shared calendar event (and
reminders) in step, while respecting decisions #3/#4 (default calendar + share sheet only,
no double-booking detection) and the local-only data model and export format.
