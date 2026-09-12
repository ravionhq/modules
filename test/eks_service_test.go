// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/ravionhq/modules/test/helpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// requireOutputNull asserts that a Terraform output is null rather than merely
// empty. terraform.Output stringifies a null value as "<nil>", which would
// silently pass an assert.Empty check, so the raw JSON is compared instead.
// The eks_service module's contract is that a disabled half of the module
// (load balancer or ECR) yields null outputs, not empty strings.
func requireOutputNull(t *testing.T, terraformOptions *terraform.Options, outputName string, msgAndArgs ...any) {
	t.Helper()

	rawOutput := strings.TrimSpace(terraform.OutputJson(t, terraformOptions, outputName))
	assert.Equal(t, "null", rawOutput, msgAndArgs...)
}

// TestEksServiceWithAlb provisions the web-shaped EKS service fixture: a
// listener ARN is supplied and ECR repository creation is left disabled.
// It verifies:
// - the target group is created with the configured port, protocol, and IP target type
// - the health check, stickiness, deregistration delay, and slow start are applied as configured
// - the listener rule is created at the configured priority and forwards to the target group
// - the load balancer outputs resolve to the ALB behind the listener
// - every ecr_* output is null
func TestEksServiceWithAlb(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("ekssvcalb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/eks_service/with_alb",
		Vars: map[string]any{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	albZoneId := terraform.Output(t, terraformOptions, "alb_zone_id")
	albArnSuffix := terraform.Output(t, terraformOptions, "alb_arn_suffix")
	listenerArn := terraform.Output(t, terraformOptions, "listener_arn")
	targetGroupArn := terraform.Output(t, terraformOptions, "target_group_arn")
	targetGroupArnSuffix := terraform.Output(t, terraformOptions, "target_group_arn_suffix")
	targetGroupName := terraform.Output(t, terraformOptions, "target_group_name")
	listenerRuleArn := terraform.Output(t, terraformOptions, "listener_rule_arn")
	listenerRulePriority := terraform.Output(t, terraformOptions, "listener_rule_priority")
	loadBalancerArn := terraform.Output(t, terraformOptions, "load_balancer_arn")
	loadBalancerDnsName := terraform.Output(t, terraformOptions, "load_balancer_dns_name")
	loadBalancerZoneId := terraform.Output(t, terraformOptions, "load_balancer_zone_id")
	loadBalancerArnSuffix := terraform.Output(t, terraformOptions, "load_balancer_arn_suffix")
	serviceVpcId := terraform.Output(t, terraformOptions, "service_vpc_id")

	// Assert target group and listener rule outputs are not empty
	require.NotEmpty(t, targetGroupArn, "target_group_arn should not be empty")
	require.NotEmpty(t, targetGroupArnSuffix, "target_group_arn_suffix should not be empty")
	require.NotEmpty(t, targetGroupName, "target_group_name should not be empty")
	require.NotEmpty(t, listenerRuleArn, "listener_rule_arn should not be empty")
	require.NotEmpty(t, listenerRulePriority, "listener_rule_priority should not be empty")

	// The module truncates the name to 24 characters before appending "-tg"
	// so the result fits the ELBv2 32 character limit. The generated test name
	// is short enough that no truncation happens.
	assert.Equal(t, uniqueName+"-tg", targetGroupName, "target group name should be the service name suffixed with -tg")
	assert.Equal(t, vpcId, serviceVpcId, "the module should report the VPC it created the target group in")

	// Use AWS SDK to verify the target group exists and is shaped for pod IPs
	targetGroupExists := helpers.TargetGroupExists(t, targetGroupArn, awsRegion)
	require.True(t, targetGroupExists, "Target group should exist in AWS")

	assert.Equal(t, uniqueName+"-tg", helpers.GetTargetGroupName(t, targetGroupArn, awsRegion), "target group name in AWS should match the output")
	assert.Equal(t, vpcId, helpers.GetTargetGroupVpcId(t, targetGroupArn, awsRegion), "target group should live in the fixture's VPC")

	// The AWS Load Balancer Controller registers pod IPs, so the target type
	// must be "ip" — an "instance" target group would register nodes instead.
	targetType := helpers.GetTargetGroupTargetType(t, targetGroupArn, awsRegion)
	assert.Equal(t, "ip", string(targetType), "Target group should use 'ip' target type so pod IPs can be registered")

	targetGroupProtocol := helpers.GetTargetGroupProtocol(t, targetGroupArn, awsRegion)
	assert.Equal(t, "HTTP", string(targetGroupProtocol), "Target group should use the configured HTTP protocol")

	targetGroupPort := helpers.GetTargetGroupPort(t, targetGroupArn, awsRegion)
	assert.Equal(t, int32(8080), targetGroupPort, "Target group should use the configured container port")

	// Verify the health check block was applied. Every value here is
	// deliberately non-default in the fixture, so a passing assertion proves
	// the module forwarded it rather than matching a coincidental default.
	assert.True(t, helpers.GetTargetGroupHealthCheckEnabled(t, targetGroupArn, awsRegion), "Health check should be enabled")
	assert.Equal(t, "/healthz", helpers.GetTargetGroupHealthCheckPath(t, targetGroupArn, awsRegion), "Health check path should match the fixture")
	assert.Equal(t, "traffic-port", helpers.GetTargetGroupHealthCheckPort(t, targetGroupArn, awsRegion), "Health check port should match the fixture")
	assert.Equal(t, "HTTP", string(helpers.GetTargetGroupHealthCheckProtocol(t, targetGroupArn, awsRegion)), "Health check protocol should match the fixture")
	assert.Equal(t, "200-299", helpers.GetTargetGroupHealthCheckMatcher(t, targetGroupArn, awsRegion), "Health check matcher should match the fixture")
	assert.Equal(t, int32(20), helpers.GetTargetGroupHealthCheckInterval(t, targetGroupArn, awsRegion), "Health check interval should match the fixture")
	assert.Equal(t, int32(7), helpers.GetTargetGroupHealthCheckTimeout(t, targetGroupArn, awsRegion), "Health check timeout should match the fixture")
	assert.Equal(t, int32(3), helpers.GetTargetGroupHealthyThreshold(t, targetGroupArn, awsRegion), "Healthy threshold should match the fixture")
	assert.Equal(t, int32(4), helpers.GetTargetGroupUnhealthyThreshold(t, targetGroupArn, awsRegion), "Unhealthy threshold should match the fixture")

	// Verify the target group attributes: deregistration delay, slow start,
	// and stickiness are all set through DescribeTargetGroupAttributes rather
	// than the target group itself.
	attributes := helpers.GetTargetGroupAttributes(t, targetGroupArn, awsRegion)
	t.Logf("Target group attributes: %v", attributes)

	assert.Equal(t, "30", attributes["deregistration_delay.timeout_seconds"], "Deregistration delay should match the fixture")
	assert.Equal(t, "60", attributes["slow_start.duration_seconds"], "Slow start duration should match the fixture")
	assert.Equal(t, "true", attributes["stickiness.enabled"], "Stickiness should be enabled")
	assert.Equal(t, "lb_cookie", attributes["stickiness.type"], "Stickiness type should match the fixture")
	assert.Equal(t, "3600", attributes["stickiness.lb_cookie.duration_seconds"], "Stickiness cookie duration should match the fixture")

	// Use AWS SDK to verify the listener rule exists and routes to the target group
	require.True(t, helpers.ListenerRuleExists(t, listenerRuleArn, awsRegion), "Listener rule should exist in AWS")

	assert.Equal(t, "100", helpers.GetListenerRulePriority(t, listenerRuleArn, awsRegion), "Listener rule should use the configured priority")
	assert.Equal(t, "100", listenerRulePriority, "listener_rule_priority output should report the configured priority")
	assert.Equal(t, targetGroupArn, helpers.GetListenerRuleTargetGroupArn(t, listenerRuleArn, awsRegion), "Listener rule should forward to the module's target group")
	assert.Equal(t, []string{"/api/*"}, helpers.GetListenerRulePathPatterns(t, listenerRuleArn, awsRegion), "Listener rule should match the configured path pattern")

	// The module owns exactly one rule on the shared listener. More than one
	// would mean it created traffic-shift machinery that EKS v1 does not have.
	ruleArns := helpers.GetListenerRuleArnsForListener(t, listenerArn, awsRegion)
	assert.Len(t, ruleArns, 1, "The module should create exactly one non-default rule on the shared listener")

	// Verify the load balancer outputs resolved from the listener back to the ALB
	assert.Equal(t, albArn, loadBalancerArn, "load_balancer_arn should resolve to the ALB behind the listener")
	assert.Equal(t, albDnsName, loadBalancerDnsName, "load_balancer_dns_name should resolve to the ALB behind the listener")
	assert.Equal(t, albZoneId, loadBalancerZoneId, "load_balancer_zone_id should resolve to the ALB behind the listener")
	assert.Equal(t, albArnSuffix, loadBalancerArnSuffix, "load_balancer_arn_suffix should resolve to the ALB behind the listener")

	albExists := helpers.LoadBalancerExists(t, loadBalancerArn, awsRegion)
	assert.True(t, albExists, "The resolved load balancer should exist in AWS")

	// ECR repository creation is disabled, so every ecr_* output must be null
	requireOutputNull(t, terraformOptions, "ecr_repository_arn", "ecr_repository_arn should be null when ecr_repository_creation_enabled is false")
	requireOutputNull(t, terraformOptions, "ecr_repository_name", "ecr_repository_name should be null when ecr_repository_creation_enabled is false")
	requireOutputNull(t, terraformOptions, "ecr_repository_url", "ecr_repository_url should be null when ecr_repository_creation_enabled is false")

	// And no repository should have been created under the service name
	assert.False(t, helpers.EcrRepositoryExists(t, uniqueName, awsRegion), "No ECR repository should exist when repository creation is disabled")
}

// TestEksServiceWorker provisions the worker/cron-shaped EKS service fixture:
// no listener ARN, ECR repository creation enabled.
// It verifies:
// - no target group and no listener rule are created
// - every load balancer output is null
// - the ECR repository exists with the expected name, scan-on-push, and tag mutability
func TestEksServiceWorker(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("ekssvcwrk")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/eks_service/worker",
		Vars: map[string]any{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Every load balancer output must be null when no listener is configured.
	// These are the values callers plumb into charts and DNS records, so a
	// stray empty string or a leftover resource would be a real regression.
	for _, outputName := range []string{
		"target_group_arn",
		"target_group_arn_suffix",
		"target_group_name",
		"listener_rule_arn",
		"listener_rule_priority",
		"load_balancer_arn",
		"load_balancer_dns_name",
		"load_balancer_zone_id",
		"load_balancer_arn_suffix",
	} {
		requireOutputNull(t, terraformOptions, outputName, "%s should be null when listener_arn is null", outputName)
	}

	// Nothing should have been created under the name the module would have
	// used, which proves the target group is genuinely absent rather than
	// merely unreported.
	assert.False(t, helpers.TargetGroupExistsByName(t, uniqueName+"-tg", awsRegion), "No target group should exist when listener_arn is null")

	// Get ECR outputs
	ecrRepositoryArn := terraform.Output(t, terraformOptions, "ecr_repository_arn")
	ecrRepositoryName := terraform.Output(t, terraformOptions, "ecr_repository_name")
	ecrRepositoryUrl := terraform.Output(t, terraformOptions, "ecr_repository_url")

	require.NotEmpty(t, ecrRepositoryArn, "ecr_repository_arn should not be empty")
	require.NotEmpty(t, ecrRepositoryName, "ecr_repository_name should not be empty")
	require.NotEmpty(t, ecrRepositoryUrl, "ecr_repository_url should not be empty")

	// With ecr_repository_name unset the repository falls back to var.name
	assert.Equal(t, uniqueName, ecrRepositoryName, "ECR repository should fall back to the service name")
	assert.True(t, strings.HasSuffix(ecrRepositoryUrl, "/"+uniqueName), "ecr_repository_url should end with the repository name, got %s", ecrRepositoryUrl)
	assert.Contains(t, ecrRepositoryUrl, ".dkr.ecr."+awsRegion+".amazonaws.com", "ecr_repository_url should point at the test region's registry")

	// Use AWS SDK to verify the repository exists and is configured as requested
	require.True(t, helpers.EcrRepositoryExists(t, ecrRepositoryName, awsRegion), "ECR repository should exist in AWS")

	assert.Equal(t, ecrRepositoryArn, helpers.GetEcrRepositoryArn(t, ecrRepositoryName, awsRegion), "ecr_repository_arn output should match the repository in AWS")
	assert.Equal(t, ecrRepositoryUrl, helpers.GetEcrRepositoryUri(t, ecrRepositoryName, awsRegion), "ecr_repository_url output should match the repository in AWS")

	tagMutability := helpers.GetEcrRepositoryImageTagMutability(t, ecrRepositoryName, awsRegion)
	assert.Equal(t, "IMMUTABLE", string(tagMutability), "ECR repository should use the configured tag mutability")

	assert.True(t, helpers.GetEcrRepositoryScanOnPushEnabled(t, ecrRepositoryName, awsRegion), "ECR repository should scan images on push")

	// The fixture opts into the ecr submodule's built-in lifecycle policy
	assert.True(t, helpers.EcrRepositoryHasLifecyclePolicy(t, ecrRepositoryName, awsRegion), "ECR repository should have the default lifecycle policy applied")
}

// TestEksServiceWithAlbAndEcr provisions an EKS service with both halves of the
// module enabled: a listener rule on a shared ALB listener and an ECR repository.
// It verifies:
// - the target group and listener rule are created and wired to each other
// - the load balancer outputs resolve to the ALB
// - the ECR repository exists alongside them with the expected settings
func TestEksServiceWithAlbAndEcr(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("ekssvcboth")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/eks_service/with_alb_and_ecr",
		Vars: map[string]any{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	listenerArn := terraform.Output(t, terraformOptions, "listener_arn")
	targetGroupArn := terraform.Output(t, terraformOptions, "target_group_arn")
	targetGroupName := terraform.Output(t, terraformOptions, "target_group_name")
	listenerRuleArn := terraform.Output(t, terraformOptions, "listener_rule_arn")
	listenerRulePriority := terraform.Output(t, terraformOptions, "listener_rule_priority")
	loadBalancerArn := terraform.Output(t, terraformOptions, "load_balancer_arn")
	loadBalancerDnsName := terraform.Output(t, terraformOptions, "load_balancer_dns_name")
	ecrRepositoryArn := terraform.Output(t, terraformOptions, "ecr_repository_arn")
	ecrRepositoryName := terraform.Output(t, terraformOptions, "ecr_repository_name")
	ecrRepositoryUrl := terraform.Output(t, terraformOptions, "ecr_repository_url")

	// The load balancer half must be fully present
	require.NotEmpty(t, targetGroupArn, "target_group_arn should not be empty")
	require.NotEmpty(t, targetGroupName, "target_group_name should not be empty")
	require.NotEmpty(t, listenerRuleArn, "listener_rule_arn should not be empty")
	require.NotEmpty(t, loadBalancerDnsName, "load_balancer_dns_name should not be empty")

	assert.Equal(t, uniqueName+"-tg", targetGroupName, "target group name should be the service name suffixed with -tg")
	assert.Equal(t, albArn, loadBalancerArn, "load_balancer_arn should resolve to the ALB behind the listener")

	require.True(t, helpers.TargetGroupExists(t, targetGroupArn, awsRegion), "Target group should exist in AWS")

	targetType := helpers.GetTargetGroupTargetType(t, targetGroupArn, awsRegion)
	assert.Equal(t, "ip", string(targetType), "Target group should use 'ip' target type so pod IPs can be registered")

	targetGroupPort := helpers.GetTargetGroupPort(t, targetGroupArn, awsRegion)
	assert.Equal(t, int32(3000), targetGroupPort, "Target group should use the configured container port")

	require.True(t, helpers.ListenerRuleExists(t, listenerRuleArn, awsRegion), "Listener rule should exist in AWS")

	assert.Equal(t, "200", helpers.GetListenerRulePriority(t, listenerRuleArn, awsRegion), "Listener rule should use the configured priority")
	assert.Equal(t, "200", listenerRulePriority, "listener_rule_priority output should report the configured priority")
	assert.Equal(t, targetGroupArn, helpers.GetListenerRuleTargetGroupArn(t, listenerRuleArn, awsRegion), "Listener rule should forward to the module's target group")
	assert.Equal(t, []string{"/*"}, helpers.GetListenerRulePathPatterns(t, listenerRuleArn, awsRegion), "Listener rule should match the configured path pattern")

	ruleArns := helpers.GetListenerRuleArnsForListener(t, listenerArn, awsRegion)
	assert.Len(t, ruleArns, 1, "The module should create exactly one non-default rule on the shared listener")

	// The ECR half must be present at the same time
	require.NotEmpty(t, ecrRepositoryArn, "ecr_repository_arn should not be empty")
	require.NotEmpty(t, ecrRepositoryName, "ecr_repository_name should not be empty")
	require.NotEmpty(t, ecrRepositoryUrl, "ecr_repository_url should not be empty")

	assert.Equal(t, uniqueName, ecrRepositoryName, "ECR repository should fall back to the service name")

	require.True(t, helpers.EcrRepositoryExists(t, ecrRepositoryName, awsRegion), "ECR repository should exist in AWS")

	tagMutability := helpers.GetEcrRepositoryImageTagMutability(t, ecrRepositoryName, awsRegion)
	assert.Equal(t, "MUTABLE", string(tagMutability), "ECR repository should use the configured tag mutability")

	assert.True(t, helpers.GetEcrRepositoryScanOnPushEnabled(t, ecrRepositoryName, awsRegion), "ECR repository should scan images on push")
	assert.Equal(t, ecrRepositoryArn, helpers.GetEcrRepositoryArn(t, ecrRepositoryName, awsRegion), "ecr_repository_arn output should match the repository in AWS")
}

// TestEksServiceEcrRepositoryNameOverride provisions an EKS service whose ECR
// repository name differs from the service name.
// It verifies:
// - the repository is created under ecr_repository_name, not var.name
// - no repository is created under var.name
func TestEksServiceEcrRepositoryNameOverride(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run, plus a distinct repository name
	uniqueName := helpers.UniqueResourceName("ekssvcrepo")
	overrideRepositoryName := helpers.UniqueResourceName("ekssvcimg")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/eks_service/with_ecr_name_override",
		Vars: map[string]any{
			"name":                uniqueName,
			"ecr_repository_name": overrideRepositoryName,
			"region":              awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	ecrRepositoryArn := terraform.Output(t, terraformOptions, "ecr_repository_arn")
	ecrRepositoryName := terraform.Output(t, terraformOptions, "ecr_repository_name")
	ecrRepositoryUrl := terraform.Output(t, terraformOptions, "ecr_repository_url")

	require.NotEmpty(t, ecrRepositoryArn, "ecr_repository_arn should not be empty")
	require.NotEmpty(t, ecrRepositoryName, "ecr_repository_name should not be empty")
	require.NotEmpty(t, ecrRepositoryUrl, "ecr_repository_url should not be empty")

	// The override wins over the fallback to var.name
	assert.Equal(t, overrideRepositoryName, ecrRepositoryName, "ecr_repository_name should override the service name")
	assert.NotEqual(t, uniqueName, ecrRepositoryName, "ecr_repository_name should not fall back to the service name when overridden")
	assert.True(t, strings.HasSuffix(ecrRepositoryUrl, "/"+overrideRepositoryName), "ecr_repository_url should end with the overridden repository name, got %s", ecrRepositoryUrl)

	// Use AWS SDK to verify the repository exists under the override only
	require.True(t, helpers.EcrRepositoryExists(t, overrideRepositoryName, awsRegion), "ECR repository should exist under the overridden name")
	assert.False(t, helpers.EcrRepositoryExists(t, uniqueName, awsRegion), "No ECR repository should exist under the service name when the name is overridden")

	assert.Equal(t, ecrRepositoryArn, helpers.GetEcrRepositoryArn(t, overrideRepositoryName, awsRegion), "ecr_repository_arn output should match the repository in AWS")

	// Defaults still apply to the rest of the repository configuration
	tagMutability := helpers.GetEcrRepositoryImageTagMutability(t, overrideRepositoryName, awsRegion)
	assert.Equal(t, "MUTABLE", string(tagMutability), "ECR repository should default to MUTABLE tag mutability")

	assert.True(t, helpers.GetEcrRepositoryScanOnPushEnabled(t, overrideRepositoryName, awsRegion), "ECR repository should default to scanning images on push")
}
