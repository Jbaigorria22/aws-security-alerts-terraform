# ADR-0002: Multi-Region trail and cross-Region event forwarding

- **Status:** Accepted
- **Date:** 2026-11-05
- **Supersedes (in part):** [ADR-0001](0001-realtime-security-alerts.md)

## Context

End-to-end test on 2026-11-05: a real root console sign-in produced **no alert**.

Diagnosis, hop by hop:

| Test | Result |
|------|--------|
| A. `sns publish` directly to the topic | Email received: SNS + subscription OK |
| B. `events put-events` with a synthetic root sign-in event in `us-east-1` | Email received: rule + target + topic policy OK |
| C. `cloudtrail lookup-events` for `ConsoleLogin` in `us-east-1` | **No event** |
| D. Same lookup across all enabled Regions | `ConsoleLogin` by `root` found in **`us-east-2`** |

The root sign-in was recorded in `us-east-2`, not `us-east-1` as ADR-0001
assumed from the docs. The single-Region trail and the `us-east-1`-only rule
never saw it. Lesson: verify with real data, do not assume.

## Decision

1. **Multi-Region trail** (`is_multi_region_trail = true`) so CloudTrail delivers
   events to EventBridge in every Region. Management events stay free for the
   first trail copy.
2. **Central Region stays `us-east-1`**: one rule per detection, target = SNS.
3. **Forwarder rules in every other enabled Region**: same patterns, target =
   the central default event bus, using an IAM role allowed only
   `events:PutEvents` on that bus.
4. Regions come from `data "aws_regions"`, and rules are created with
   `for_each` + `setproduct` and the AWS provider v6 per-resource `region`
   argument (one provider, no aliases).
5. **Patterns now require `source`** (`aws.signin`, `aws.cloudtrail`, `aws.ec2`).
   Test B showed that without it, anyone with `events:PutEvents` could trigger
   fake alerts. `aws.*` sources cannot be sent with `PutEvents`.
6. The existing root rule is refactored with `moved` blocks, so it is updated
   in place instead of destroyed and recreated.

## Consequences

- Detections now cover all enabled Regions.
- About 3 forwarder rules per Region. EventBridge rules are free; only matching
  events are forwarded, so cost is negligible.
- Synthetic test events can no longer trigger alerts. Tests must use real
  actions (see README).
- Regions enabled later require a new `terraform apply`.
