# aws-security-alerts-terraform

Real-time AWS security alerts, fully provisioned with Terraform.
A hands-on lab built while preparing for the **HashiCorp Terraform Associate (004)** exam.

```
AWS action (any Region) → multi-Region CloudTrail → EventBridge
   ├─ us-east-1: central rule ────────────────────────────────→ SNS → email
   └─ other Regions: forwarder rule → us-east-1 default bus ──┘
```

## Detections

| Detection | Trigger |
|-----------|---------|
| `root_login` | Root user signs in to the console |
| `cloudtrail_tampering` | `StopLogging` or `DeleteTrail` |
| `sg_open_to_world` | Security group ingress opened to `0.0.0.0/0` or `::/0` |

## What is provisioned

- Private, encrypted S3 bucket for CloudTrail logs (30-day expiration)
- Multi-Region CloudTrail trail (management events)
- SNS topic with email subscription
- One central EventBridge rule per detection in `us-east-1`
- Forwarder rules in every other enabled Region + IAM role to forward events

## Design decisions

- [ADR-0001: Real-time security alerts](docs/adr/0001-realtime-security-alerts.md)
- [ADR-0002: Multi-Region trail and cross-Region forwarding](docs/adr/0002-multi-region-forwarding.md):
  includes the hop-by-hop debugging that found root sign-ins being recorded in `us-east-2`.

## Terraform concepts practiced

Providers and version constraints, lock file, input variables with `validation`
and `sensitive`, `locals`, `resource` vs `data`, implicit dependencies and
`depends_on`, `jsonencode`, `for_each`, `setproduct`, `for` expressions,
`moved` blocks, outputs, saved plans (`plan -out`), state inspection.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # set alert_email
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Confirm the SNS subscription email before testing.

## Testing

1. **Root sign-in:** sign in as root (with MFA), wait 1–5 minutes, check email. Sign out.
2. **Security group:** in any Region, create a test security group, add an inbound
   rule from `0.0.0.0/0`, wait for the email, then delete the group.

## Cleanup

```bash
terraform destroy
```
