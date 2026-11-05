# ADR-0001: Real-time security alerts with CloudTrail, EventBridge and SNS

- **Status:** Accepted, partially superseded by [ADR-0002](0002-multi-region-forwarding.md)
- **Date:** 2026-11-05

## Context

Small hands-on lab to practice Terraform (Terraform Associate prep) on a real
AWS account. Goal: get an email within minutes when a high-risk action happens.

Constraints:
- Budget alert at USD 5/month: everything must stay within free usage or near zero.
- Everything is provisioned with Terraform. No manual console changes.

## Decision

```
AWS action → CloudTrail (trail) → EventBridge rule (event pattern) → SNS topic → email
```

v0 detections:

| # | Detection | Event |
|---|-----------|-------|
| 1 | Root user console sign-in | `AWS Console Sign In via CloudTrail`, `userIdentity.type = Root` |
| 2 | CloudTrail logging stopped | `cloudtrail.amazonaws.com` / `StopLogging` |
| 3 | Security group opened to the internet | `ec2.amazonaws.com` / `AuthorizeSecurityGroupIngress` with `0.0.0.0/0` |

Design choices:
- **Region: `us-east-1` only.** AWS docs state root sign-in events are recorded
  in `us-east-1`, and EventBridge rules are regional. *(Superseded by ADR-0002.)*
- **A CloudTrail trail is created by this lab.** EventBridge only receives
  CloudTrail detail-types when a trail with logging is enabled in the same Region.
- **Single-Region trail, management events only.** *(Superseded by ADR-0002.)*
- **S3 log bucket:** private, encrypted (SSE-S3), objects expire after 30 days.
  `force_destroy = true` because this is a lab.
- **SNS email** as the notification channel.

## Consequences

- Events recorded outside `us-east-1` are not detected. *(This turned out to be
  the real failure mode, see ADR-0002.)*
- Alert emails contain raw event JSON.
- EventBridge delivery of CloudTrail events is best effort: a learning tripwire,
  not a production-grade control.

## References

- [AWS service events delivered via CloudTrail (EventBridge User Guide)](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html)
- [Root user sign-in EventBridge rule (AWS re:Post)](https://repost.aws/knowledge-center/root-user-account-eventbridge-rule)
- [Console sign-in events (CloudTrail User Guide)](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference-aws-console-sign-in-events.html)
