# Basic ALB Module Tests
# Run with: tofu test

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_elb_service_account.current
    values = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  # Override resources that need valid ARNs
  override_resource {
    target = aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-alb/1234567890123456"
      arn_suffix = "app/test-alb/1234567890123456"
      dns_name   = "test-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = aws_lb_listener.http
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-alb/1234567890123456/1234567890123456"
    }
  }

  override_resource {
    target = aws_lb_listener.https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-alb/1234567890123456/6543210987654321"
    }
  }

  override_resource {
    target = module.security_group.aws_security_group.this
    values = {
      arn      = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-1234567890abcdef0"
      id       = "sg-1234567890abcdef0"
      owner_id = "123456789012"
    }
  }

  override_resource {
    target = aws_s3_bucket.access_logs
    values = {
      arn = "arn:aws:s3:::test-alb-access-logs-123456789012-us-east-1"
      id  = "test-alb-access-logs-123456789012-us-east-1"
    }
  }
}

variables {
  name       = "test-alb"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-12345678", "subnet-87654321"]
}

# Test 1: Basic ALB with defaults (HTTP only)
run "basic_alb_http_only" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == false
    error_message = "ALB should be internet-facing by default"
  }

  assert {
    condition     = aws_lb.this.load_balancer_type == "application"
    error_message = "ALB should be of type application"
  }

  assert {
    condition     = length(aws_lb_listener.http) == 1
    error_message = "HTTP listener should be created by default"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "HTTPS listener should not be created by default"
  }

  assert {
    condition     = var.access_logs_retention_days == 365
    error_message = "access_logs_retention_days should default to 365"
  }
}

# Test 2: Internal ALB
run "internal_alb" {
  command = plan

  variables {
    internal = true
  }

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "ALB should be internal when internal = true"
  }
}

# Test 3: HTTPS listener enabled with certificate
run "https_listener_enabled" {
  command = plan

  variables {
    https_listener_enabled = true
    certificate_arns       = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "HTTPS listener should be created when enabled with certificate"
  }

  assert {
    condition     = aws_lb_listener.https[0].port == 443
    error_message = "HTTPS listener should use port 443 by default"
  }

  assert {
    condition     = aws_lb_listener.https[0].protocol == "HTTPS"
    error_message = "HTTPS listener should use HTTPS protocol"
  }
}

# Test 4: HTTP to HTTPS redirect
run "http_to_https_redirect" {
  command = plan

  variables {
    https_listener_enabled         = true
    certificate_arns               = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
    http_to_https_redirect_enabled = true
  }

  assert {
    condition     = length(aws_lb_listener.http) == 1
    error_message = "HTTP listener should be created"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "HTTPS listener should be created"
  }

  # The HTTP listener should have a redirect action when both listeners exist and redirect is enabled
  assert {
    condition     = aws_lb_listener.http[0].default_action[0].type == "redirect"
    error_message = "HTTP listener should redirect to HTTPS when http_to_https_redirect_enabled is true"
  }
}

# Test 5: HTTP listener with fixed response (no redirect)
run "http_no_redirect" {
  command = plan

  variables {
    https_listener_enabled         = true
    certificate_arns               = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
    http_to_https_redirect_enabled = false
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].type == "fixed-response"
    error_message = "HTTP listener should return fixed response when redirect is disabled"
  }
}

# Test 6: HTTP listener disabled
run "http_listener_disabled" {
  command = plan

  variables {
    http_listener_enabled  = false
    https_listener_enabled = true
    certificate_arns       = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
  }

  assert {
    condition     = length(aws_lb_listener.http) == 0
    error_message = "HTTP listener should not be created when disabled"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "HTTPS listener should be created"
  }
}

# Test 7: Custom default action
run "custom_default_action" {
  command = plan

  variables {
    default_action_status_code  = 404
    default_action_message      = "Not Found"
    default_action_content_type = "text/plain"
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].fixed_response[0].status_code == "404"
    error_message = "Default action should use custom status code"
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].fixed_response[0].message_body == "Not Found"
    error_message = "Default action should use custom message"
  }
}

# Test 8: Custom ports
run "custom_ports" {
  command = plan

  variables {
    http_listener_port     = 8080
    https_listener_port    = 8443
    https_listener_enabled = true
    certificate_arns       = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
  }

  assert {
    condition     = aws_lb_listener.http[0].port == 8080
    error_message = "HTTP listener should use custom port 8080"
  }

  assert {
    condition     = aws_lb_listener.https[0].port == 8443
    error_message = "HTTPS listener should use custom port 8443"
  }
}

# Test 9: Access logs with new bucket
run "access_logs_new_bucket" {
  command = plan

  variables {
    access_logs_enabled        = true
    access_logs_retention_days = 90
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 1
    error_message = "S3 bucket should be created for access logs"
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.access_logs) == 1
    error_message = "S3 bucket should block public access"
  }

  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.access_logs) == 1
    error_message = "S3 bucket should have encryption configured"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.access_logs) == 1
    error_message = "S3 bucket should have lifecycle configuration"
  }
}

# Test 10: Access logs with existing bucket
run "access_logs_existing_bucket" {
  command = plan

  variables {
    access_logs_enabled    = true
    access_logs_bucket_arn = "arn:aws:s3:::my-existing-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 0
    error_message = "S3 bucket should not be created when existing ARN provided"
  }
}

# Test 11: Access logs disabled
run "access_logs_disabled" {
  command = plan

  variables {
    access_logs_enabled = false
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 0
    error_message = "S3 bucket should not be created when access logs disabled"
  }
}

# Test 12: WAF enabled
run "waf_enabled" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test-waf/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "WAF association should be created when web_acl_arn provided"
  }
}

# Test 13: WAF disabled
run "waf_disabled" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "WAF association should not be created when web_acl_arn not provided"
  }
}

# Test 14: Security settings defaults
run "security_settings_defaults" {
  command = plan

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "drop_invalid_header_fields should be true by default"
  }

  assert {
    condition     = aws_lb.this.desync_mitigation_mode == "defensive"
    error_message = "desync_mitigation_mode should be 'defensive' by default"
  }

  assert {
    condition     = aws_lb.this.enable_http2 == true
    error_message = "HTTP/2 should be enabled by default"
  }
}

# Test 15: Resource tagging
run "resource_tagging" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      Project     = "myproject"
    }
  }

  assert {
    condition     = aws_lb.this.tags["Environment"] == "test"
    error_message = "ALB should have Environment tag"
  }

  assert {
    condition     = aws_lb.this.tags["ManagedBy"] == "terraform"
    error_message = "ALB should have default ManagedBy tag"
  }
}

# Test 16: Security group created
run "security_group_created" {
  command = plan

  assert {
    condition     = module.security_group.aws_security_group.this.vpc_id == "vpc-12345678"
    error_message = "Security group should be created in the specified VPC"
  }

  assert {
    condition     = module.security_group.aws_security_group.this.name == "test-alb-alb"
    error_message = "Security group should have correct name"
  }
}

# Test 17: Security group ingress rules for HTTP
run "security_group_http_ingress" {
  command = plan

  assert {
    condition     = length(module.security_group.aws_vpc_security_group_ingress_rule.this) > 0
    error_message = "HTTP ingress rules should be created when HTTP listener enabled"
  }
}

# Test 18: Security group ingress rules for HTTPS
run "security_group_https_ingress" {
  command = plan

  variables {
    https_listener_enabled = true
    certificate_arns       = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
  }

  assert {
    condition     = length(module.security_group.aws_vpc_security_group_ingress_rule.this) > 0
    error_message = "HTTPS ingress rules should be created when HTTPS listener enabled"
  }
}

# Test 19: Security group egress rule
run "security_group_egress" {
  command = plan

  assert {
    condition     = length(module.security_group.aws_vpc_security_group_egress_rule.allow_all_ipv4) == 1
    error_message = "Egress rule should allow all IPv4 traffic"
  }

  assert {
    condition     = length(module.security_group.aws_vpc_security_group_egress_rule.allow_all_ipv6) == 1
    error_message = "Egress rule should allow all IPv6 traffic"
  }
}

# Test 20: Custom ingress CIDR blocks
run "custom_ingress_cidrs" {
  command = plan

  variables {
    ingress_cidr_blocks      = ["10.0.0.0/8", "172.16.0.0/12"]
    ingress_ipv6_cidr_blocks = []
  }

  assert {
    condition     = length(module.security_group.aws_vpc_security_group_ingress_rule.this) > 0
    error_message = "HTTP ingress rules should be created with custom CIDR blocks"
  }
}

# Test 21: Custom idle timeout
run "custom_idle_timeout" {
  command = plan

  variables {
    idle_timeout = 120
  }

  assert {
    condition     = aws_lb.this.idle_timeout == 120
    error_message = "ALB should use custom idle timeout"
  }
}

# Test 22: Custom SSL policy
run "custom_ssl_policy" {
  command = plan

  variables {
    https_listener_enabled = true
    certificate_arns       = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
    ssl_policy             = "ELBSecurityPolicy-TLS-1-2-2017-01"
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS-1-2-2017-01"
    error_message = "HTTPS listener should use custom SSL policy"
  }
}

# Test 23: Deletion protection
run "deletion_protection" {
  command = plan

  variables {
    deletion_protection_enabled = true
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "ALB should have deletion protection enabled"
  }
}

# Test 24: Additional certificates (SNI)
run "additional_certificates" {
  command = plan

  variables {
    https_listener_enabled = true
    certificate_arns = [
      "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012",
      "arn:aws:acm:us-east-1:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      "arn:aws:acm:us-east-1:123456789012:certificate/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    ]
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 2
    error_message = "Should create 2 additional listener certificates"
  }
}

# Test 25: No additional certificates when HTTPS disabled
run "no_additional_certs_without_https" {
  command = plan

  variables {
    https_listener_enabled = false
    certificate_arns = [
      "arn:aws:acm:us-east-1:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    ]
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 0
    error_message = "Should not create additional certificates when HTTPS disabled"
  }
}

# Test 26: Preserve host header
run "preserve_host_header" {
  command = plan

  variables {
    preserve_host_header = true
  }

  assert {
    condition     = aws_lb.this.preserve_host_header == true
    error_message = "ALB should preserve host header when enabled"
  }
}

# Test 27: XFF header processing mode
run "xff_header_processing" {
  command = plan

  variables {
    xff_header_processing_mode = "preserve"
  }

  assert {
    condition     = aws_lb.this.xff_header_processing_mode == "preserve"
    error_message = "ALB should use custom XFF header processing mode"
  }
}

# Test 28: WAF fail open
run "waf_fail_open" {
  command = plan

  variables {
    waf_fail_open_enabled = true
  }

  assert {
    condition     = aws_lb.this.enable_waf_fail_open == true
    error_message = "ALB should have WAF fail open enabled"
  }
}

# Test 29: Ingress rules referencing source security groups
run "ingress_security_groups" {
  command = plan

  variables {
    https_listener_enabled     = true
    certificate_arns           = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
    ingress_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition = length([
      for rule in module.security_group.aws_vpc_security_group_ingress_rule.this : rule
      if rule.referenced_security_group_id == "sg-0123456789abcdef0"
    ]) == 2
    error_message = "Should create HTTP and HTTPS ingress rules referencing the source security group"
  }

  assert {
    condition = length([
      for rule in module.security_group.aws_vpc_security_group_ingress_rule.this : rule
      if rule.referenced_security_group_id == "sg-0123456789abcdef0" && rule.from_port == 443
    ]) == 1
    error_message = "Should create an HTTPS ingress rule referencing the source security group"
  }
}

# Test 30: No security group referenced ingress rules by default
run "no_ingress_security_groups_by_default" {
  command = plan

  assert {
    condition = length([
      for rule in module.security_group.aws_vpc_security_group_ingress_rule.this : rule
      if rule.referenced_security_group_id != null
    ]) == 0
    error_message = "Should not create security group referenced ingress rules by default"
  }
}

# Test 31: CloudWatch alarms can be disabled explicitly
run "cloudwatch_alarms_disabled" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = false
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.elb_5xx) == 0 && length(aws_cloudwatch_metric_alarm.target_5xx) == 0 && length(aws_cloudwatch_metric_alarm.target_response_time) == 0
    error_message = "No CloudWatch alarms should be created when explicitly disabled"
  }

  assert {
    condition     = length(output.cloudwatch_alarm_arns) == 0
    error_message = "cloudwatch_alarm_arns output should be empty when alarms are disabled"
  }
}

# Test 32: CloudWatch alarms enabled with defaults
run "cloudwatch_alarms_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.elb_5xx) == 1 && length(aws_cloudwatch_metric_alarm.target_5xx) == 1 && length(aws_cloudwatch_metric_alarm.target_response_time) == 1
    error_message = "All three CloudWatch alarms should be created when enabled"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].dimensions["LoadBalancer"] == "app/test-alb/1234567890123456"
    error_message = "Alarms should use the ALB ARN suffix as the LoadBalancer dimension"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].namespace == "AWS/ApplicationELB" && aws_cloudwatch_metric_alarm.elb_5xx[0].metric_name == "HTTPCode_ELB_5XX_Count" && aws_cloudwatch_metric_alarm.elb_5xx[0].statistic == "Sum"
    error_message = "ELB 5xx alarm should sum HTTPCode_ELB_5XX_Count in AWS/ApplicationELB"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.target_5xx[0].metric_name == "HTTPCode_Target_5XX_Count" && aws_cloudwatch_metric_alarm.target_5xx[0].statistic == "Sum"
    error_message = "Target 5xx alarm should sum HTTPCode_Target_5XX_Count"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.target_response_time[0].metric_name == "TargetResponseTime" && aws_cloudwatch_metric_alarm.target_response_time[0].statistic == "Average"
    error_message = "Target response time alarm should average TargetResponseTime"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].threshold == 10 && aws_cloudwatch_metric_alarm.target_5xx[0].threshold == 10 && aws_cloudwatch_metric_alarm.target_response_time[0].threshold == 1
    error_message = "Alarms should use the default thresholds"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].evaluation_periods == 2 && aws_cloudwatch_metric_alarm.elb_5xx[0].period == 300
    error_message = "Alarms should use the default evaluation periods and period"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].treat_missing_data == "notBreaching"
    error_message = "Alarms should treat missing data as not breaching"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].alarm_name == "test-alb-alb-elb-5xx"
    error_message = "ELB 5xx alarm name should be prefixed with the module name"
  }
}

# Test 33: CloudWatch alarms with custom thresholds and actions
run "cloudwatch_alarms_custom" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled              = true
    cloudwatch_alarm_elb_5xx_threshold              = 50
    cloudwatch_alarm_target_5xx_threshold           = 25
    cloudwatch_alarm_target_response_time_threshold = 2.5
    cloudwatch_alarm_evaluation_periods             = 3
    cloudwatch_alarm_period                         = 60
    cloudwatch_alarm_actions                        = ["arn:aws:sns:us-east-1:123456789012:alerts"]
    cloudwatch_ok_actions                           = ["arn:aws:sns:us-east-1:123456789012:recovered"]
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.elb_5xx[0].threshold == 50 && aws_cloudwatch_metric_alarm.target_5xx[0].threshold == 25 && aws_cloudwatch_metric_alarm.target_response_time[0].threshold == 2.5
    error_message = "Alarms should use the custom thresholds"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.target_5xx[0].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.target_5xx[0].period == 60
    error_message = "Alarms should use the custom evaluation periods and period"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.target_response_time[0].alarm_actions) == 1 && contains(aws_cloudwatch_metric_alarm.target_response_time[0].alarm_actions, "arn:aws:sns:us-east-1:123456789012:alerts")
    error_message = "Alarms should notify the configured alarm actions"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.target_response_time[0].ok_actions) == 1 && contains(aws_cloudwatch_metric_alarm.target_response_time[0].ok_actions, "arn:aws:sns:us-east-1:123456789012:recovered")
    error_message = "Alarms should notify the configured OK actions"
  }
}

run "cloudwatch_alarms_null_uses_default" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = null
  }

  assert {
    condition     = length(output.cloudwatch_alarm_arns) == 3 && length(aws_cloudwatch_metric_alarm.elb_5xx) == 1 && length(aws_cloudwatch_metric_alarm.target_5xx) == 1 && length(aws_cloudwatch_metric_alarm.target_response_time) == 1
    error_message = "Expected alarms to be enabled by default, including null input"
  }
}
