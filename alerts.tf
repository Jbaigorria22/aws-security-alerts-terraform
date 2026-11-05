# =============================================================================
# Detections (EventBridge) and notifications (SNS)
#
# Design (ADR-0002):
#   - Central Region (var.aws_region = us-east-1): one rule per detection -> SNS.
#   - Every other enabled Region: one "forwarder" rule per detection that sends
#     matching events to the central default event bus.
# =============================================================================

locals {
  # One entry per detection. The pattern is stored as a JSON string so every
  # entry has the same shape (description + pattern) and for_each accepts it.
  detections = {
    root_login = {
      description = "Root user signed in to the AWS console"
      pattern = jsonencode({
        source        = ["aws.signin"]
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail = {
          userIdentity = { type = ["Root"] }
        }
      })
    }

    cloudtrail_tampering = {
      description = "CloudTrail logging stopped or trail deleted"
      pattern = jsonencode({
        source        = ["aws.cloudtrail"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["StopLogging", "DeleteTrail"]
        }
      })
    }

    sg_open_to_world = {
      description = "Security group ingress opened to 0.0.0.0/0 or ::/0"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName   = ["AuthorizeSecurityGroupIngress"]
          "$or" = [
            { requestParameters = { ipPermissions = { items = { ipRanges = { items = { cidrIp = ["0.0.0.0/0"] } } } } } },
            { requestParameters = { ipPermissions = { items = { ipv6Ranges = { items = { cidrIpv6 = ["::/0"] } } } } } },
          ]
        }
      })
    }
  }

  central_bus_arn = "arn:aws:events:${var.aws_region}:${local.account_id}:event-bus/default"

  # Every enabled Region except the central one.
  forward_regions = sort(tolist(setsubtract(data.aws_regions.enabled.names, [var.aws_region])))

  # Every (Region, detection) combination, e.g. "us-east-2/root_login".
  forwarders = {
    for pair in setproduct(local.forward_regions, keys(local.detections)) :
    "${pair[0]}/${pair[1]}" => {
      region    = pair[0]
      detection = pair[1]
    }
  }
}

# Regions enabled in this account (read during plan).
data "aws_regions" "enabled" {}

# -----------------------------------------------------------------------------
# SNS: the "phone"
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-topic"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -----------------------------------------------------------------------------
# Central rules (us-east-1): one per detection -> SNS
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "central" {
  for_each = local.detections

  name          = "${var.project_name}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  event_pattern = each.value.pattern
}

resource "aws_cloudwatch_event_target" "central" {
  for_each = local.detections

  rule      = aws_cloudwatch_event_rule.central[each.key].name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}

# Only our central rules may publish to the topic.
data "aws_iam_policy_document" "sns_topic" {
  statement {
    sid       = "AllowEventBridgePublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for rule in aws_cloudwatch_event_rule.central : rule.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_topic.json
}

# Refactor without recreating: the old single rule becomes central["root_login"].
moved {
  from = aws_cloudwatch_event_rule.root_login
  to   = aws_cloudwatch_event_rule.central["root_login"]
}

moved {
  from = aws_cloudwatch_event_target.root_login_to_sns
  to   = aws_cloudwatch_event_target.central["root_login"]
}

# -----------------------------------------------------------------------------
# Forwarders: every other Region -> central default event bus
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "forwarder_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "forwarder" {
  name               = "${var.project_name}-event-forwarder"
  assume_role_policy = data.aws_iam_policy_document.forwarder_assume.json
}

data "aws_iam_policy_document" "forwarder_put_events" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [local.central_bus_arn]
  }
}

resource "aws_iam_role_policy" "forwarder" {
  name   = "put-events-to-central-bus"
  role   = aws_iam_role.forwarder.id
  policy = data.aws_iam_policy_document.forwarder_put_events.json
}

resource "aws_cloudwatch_event_rule" "forward" {
  for_each = local.forwarders

  region        = each.value.region # AWS provider v6: per-resource Region
  name          = "${var.project_name}-fwd-${replace(each.value.detection, "_", "-")}"
  description   = "Forward to ${var.aws_region}: ${local.detections[each.value.detection].description}"
  event_pattern = local.detections[each.value.detection].pattern
}

resource "aws_cloudwatch_event_target" "forward" {
  for_each = local.forwarders

  region    = each.value.region
  rule      = aws_cloudwatch_event_rule.forward[each.key].name
  target_id = "central-bus"
  arn       = local.central_bus_arn
  role_arn  = aws_iam_role.forwarder.arn
}
