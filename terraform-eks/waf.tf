resource "aws_wafv2_web_acl" "vulntrack" {
  name        = "${var.project_name}-waf"
  description = "WAF for the VulnTrack ALB - AWS managed rule groups plus rate limiting"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Blocks common web exploits: XSS, malformed requests, oversized bodies, etc.
  rule {
    name     = "AWS-CommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Blocks known malicious request patterns (scanners, exploit attempts)
  rule {
    name     = "AWS-KnownBadInputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSKnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # SQL injection protection — a thematically fitting inclusion given this
  # is a vulnerability-tracking application.
  rule {
    name     = "AWS-SQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting: WAF rate-based rules count over a fixed 5-minute window, so
  # a 600 requests/minute target is expressed as 3000 per 5 minutes. Counted
  # per source IP; an IP over the limit is blocked until its rate drops.
  rule {
    name     = "RateLimit"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 3000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Blocks requests whose User-Agent matches common scanning and enumeration
  # tools. This stops opportunistic automated scanning only - a user agent is
  # trivially changed, so anyone deliberate walks straight past it. Managed Bot
  # Control does behavioural detection but costs $10/month; this is the free
  # tier of the same idea and its limits are understood rather than assumed.
  rule {
    name     = "BlockScannerUserAgents"
    priority = 5

    action {
      block {}
    }

    statement {
      or_statement {
        dynamic "statement" {
          for_each = ["nikto", "sqlmap", "nmap", "masscan", "dirbuster", "gobuster", "wpscan", "nessus", "acunetix", "havij"]
          content {
            byte_match_statement {
              search_string         = statement.value
              positional_constraint = "CONTAINS"

              field_to_match {
                single_header {
                  name = "user-agent"
                }
              }

              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockScannerUserAgents"
      sampled_requests_enabled   = true
    }
  }

  # The Common Rule Set caps individual fields (body, query string, cookie
  # header) but not the total size of all headers. Oversized header sets are a
  # cheap denial-of-service vector and have no legitimate use here.
  rule {
    name     = "BlockOversizedHeaders"
    priority = 6

    action {
      block {}
    }

    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = 8192

        field_to_match {
          headers {
            match_scope = "ALL"

            match_pattern {
              all {}
            }

            oversize_handling = "MATCH"
          }
        }

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockOversizedHeaders"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }
}


output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.vulntrack.arn
}

# The WAF Web ACL is attached via the ALB Ingress annotation instead:
#   alb.ingress.kubernetes.io/wafv2-acl-arn: <waf_web_acl_arn output>
# The ALB is created by the AWS Load Balancer Controller, so its ARN isn't
# knowable at plan time; a hardcoded one breaks on every destroy/recreate.
