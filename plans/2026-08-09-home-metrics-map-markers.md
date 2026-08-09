# Home metrics and map markers

- Commit reviewed: `fed643c`
- Scope: subscription overview counters and world-map region markers
- Status: approved by the requested behavior; ready to implement

## Why motion helps

Adding, refreshing, filtering, or re-enabling a subscription changes several
numbers and map regions at once. Today those values replace instantly, so it is
hard to tell what changed. The motion should connect the user's action to the
changed data without moving surrounding layout.

## Change 1: numeric value transition

- File: `Tower/Design/TowerTheme.swift:112`
- Caller: `Tower/Features/Subscriptions/SubscriptionsView.swift:189`
- Replace the plain string-only metric with an integer-aware value.
- Use SwiftUI's numeric text content transition and monospaced digits.
- Animate with a critically damped spring (`response` about 0.34,
  `dampingFraction` 1) when the integer changes.
- Keep the metric frame fixed so neighbouring dividers and labels do not move.
- With Reduce Motion enabled, use a short opacity transition without vertical
  number rolling.

## Change 2: map marker lighting

- File: `Tower/Features/Subscriptions/WorldDotMapView.swift:151`
- New region markers enter at 92% scale and zero opacity, then settle at full
  size and opacity using a critically damped spring (`response` about 0.36,
  `dampingFraction` 1).
- Apply a short, capped stagger based on the marker's stable sorted index so a
  large import reads as regions lighting up, while input remains available.
- Keep each marker's position and label placement unchanged.
- Replace selected-state frame changes with a fixed frame plus scale effect so
  selection does not participate in layout.
- With Reduce Motion enabled, remove scaling and stagger; use only a short
  opacity fade.

## Acceptance

- Adding or enabling nodes rolls the four overview counts to their new values.
- Newly resolved regions light up in place; existing markers do not replay.
- Selecting a region does not move neighbouring labels or markers.
- VoiceOver labels and hit areas are unchanged.
- Reduce Motion removes positional and scale motion.
- Existing world-map layout tests continue to pass.
