variable "alb_arn" {
  description = "ARN of the ALB created by the Kubernetes Ingress. Not Terraform-managed (created by the AWS Load Balancer Controller), so this is a manual reference — update if the Ingress is ever deleted and recreated, which generates a new ALB."
  type        = string
  default     = "arn:aws:elasticloadbalancing:us-east-2:825990809758:loadbalancer/app/k8s-default-vulntrac-6b0eb6143e/4731378caaf8a85d"
}

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

  # Rate limiting: blocks any single IP exceeding 2000 requests per 5-minute
  # window — a basic defense against brute-force/scraping without being
  # aggressive enough to affect normal testing traffic.
  rule {
    name     = "RateLimit"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "vulntrack" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.vulntrack.arn
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.vulntrack.arn
}
