# Participation and stakeholder history

`withdraw_participation()` ends the current account's further participation.
It requires the explicit synthetic policy `synthetic_retain_prior_data`: previously
confirmed research data and submissions remain. Further saves and submissions
are rejected, and the participant is no longer eligible for new round assignments
or local-sink messages. Previously completed deliveries are not undone.

The panel interface explains retention and requires explicit confirmation before
showing a durable withdrawal receipt. The service derives the participant from
the current server identity; it accepts no arbitrary participant ID. Identical
retries return the same receipt. Migration `009_participation.sql` protects events
from later changes. Saves and withdrawal serialize on the enrollment; preparation
of new rounds and withdrawal coordinate through the study lock.

`set_panel_group()` records a reasoned stakeholder-group change by a study manager.
It applies only to subsequently prepared rounds. Existing enrollments and frozen
analyses keep their previous group assignment. The previous group, new group,
actor and timestamp remain in an event.

This tested synthetic policy is **not a production deletion or retention rule**.
Real requests, institutional deadlines, approvals and permitted deletion require
the separate governance process. This service performs no automatic deletion.
