// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"context"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/applicationautoscaling"
	applicationautoscalingtypes "github.com/aws/aws-sdk-go-v2/service/applicationautoscaling/types"
	"github.com/aws/aws-sdk-go-v2/service/autoscaling"
	autoscalingtypes "github.com/aws/aws-sdk-go-v2/service/autoscaling/types"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ecr"
	ecrtypes "github.com/aws/aws-sdk-go-v2/service/ecr/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	ecstypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/aws/aws-sdk-go-v2/service/elasticache"
	elbv2 "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	elbv2types "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2/types"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/aws-sdk-go-v2/service/wafv2"
	wafv2types "github.com/aws/aws-sdk-go-v2/service/wafv2/types"
	"github.com/stretchr/testify/require"
)

// GetAwsRegion returns the AWS region to use for tests.
// It reads the AWS_REGION environment variable, defaulting to "us-east-1" if not set.
func GetAwsRegion() string {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		return "us-east-1"
	}
	return region
}

// getEC2Client creates an EC2 client for the specified region.
func getEC2Client(t *testing.T, region string) *ec2.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return ec2.NewFromConfig(cfg)
}

// VpcExists checks if a VPC with the given ID exists in the specified region.
func VpcExists(t *testing.T, vpcId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	if err != nil {
		// If the VPC doesn't exist, AWS returns an error
		return false
	}

	return len(result.Vpcs) > 0
}

// SubnetsExist checks if all the given subnet IDs exist in the specified region.
func SubnetsExist(t *testing.T, subnetIds []string, region string) bool {
	if len(subnetIds) == 0 {
		return false
	}

	client := getEC2Client(t, region)

	input := &ec2.DescribeSubnetsInput{
		SubnetIds: subnetIds,
	}

	result, err := client.DescribeSubnets(context.TODO(), input)
	if err != nil {
		// If any subnet doesn't exist, AWS returns an error
		return false
	}

	// Verify we got back all the subnets we asked for
	return len(result.Subnets) == len(subnetIds)
}

// GetVpcCidr returns the primary CIDR block for the specified VPC.
// It fails the test if the VPC doesn't exist or has no CIDR block.
func GetVpcCidr(t *testing.T, vpcId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC %s", vpcId)
	require.Len(t, result.Vpcs, 1, "Expected exactly one VPC with ID %s", vpcId)

	vpc := result.Vpcs[0]
	require.NotNil(t, vpc.CidrBlock, "VPC %s has no CIDR block", vpcId)

	return *vpc.CidrBlock
}

// GetVpcState returns the state of the specified VPC.
func GetVpcState(t *testing.T, vpcId string, region string) types.VpcState {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC %s", vpcId)
	require.Len(t, result.Vpcs, 1, "Expected exactly one VPC with ID %s", vpcId)

	return result.Vpcs[0].State
}

// GetNatGatewayState returns the state of a NAT Gateway.
// Returns the state as a string (pending, failed, available, deleting, deleted).
func GetNatGatewayState(t *testing.T, natGatewayId string, region string) types.NatGatewayState {
	client := getEC2Client(t, region)

	input := &ec2.DescribeNatGatewaysInput{
		NatGatewayIds: []string{natGatewayId},
	}

	result, err := client.DescribeNatGateways(context.TODO(), input)
	require.NoError(t, err, "Failed to describe NAT Gateway %s", natGatewayId)
	require.Len(t, result.NatGateways, 1, "Expected exactly one NAT Gateway with ID %s", natGatewayId)

	return result.NatGateways[0].State
}

// NatGatewayExists checks if a NAT Gateway with the given ID exists in the specified region.
func NatGatewayExists(t *testing.T, natGatewayId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeNatGatewaysInput{
		NatGatewayIds: []string{natGatewayId},
	}

	result, err := client.DescribeNatGateways(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.NatGateways) > 0
}

// RouteTableHasNatGatewayRoute checks if a route table has a route to a NAT Gateway.
// It looks for a route with destination 0.0.0.0/0 pointing to a NAT Gateway.
func RouteTableHasNatGatewayRoute(t *testing.T, routeTableId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeRouteTablesInput{
		RouteTableIds: []string{routeTableId},
	}

	result, err := client.DescribeRouteTables(context.TODO(), input)
	require.NoError(t, err, "Failed to describe route table %s", routeTableId)
	require.Len(t, result.RouteTables, 1, "Expected exactly one route table with ID %s", routeTableId)

	for _, route := range result.RouteTables[0].Routes {
		// Check for default route (0.0.0.0/0) pointing to a NAT Gateway
		if route.DestinationCidrBlock != nil && *route.DestinationCidrBlock == "0.0.0.0/0" {
			if route.NatGatewayId != nil && *route.NatGatewayId != "" {
				return true
			}
		}
	}

	return false
}

// getELBv2Client creates an ELBv2 client for the specified region.
func getELBv2Client(t *testing.T, region string) *elbv2.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return elbv2.NewFromConfig(cfg)
}

// GetLoadBalancerState returns the state of an Application Load Balancer.
// Returns the state code (active, provisioning, active_impaired, failed).
func GetLoadBalancerState(t *testing.T, albArn string, region string) elbv2types.LoadBalancerStateEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancersInput{
		LoadBalancerArns: []string{albArn},
	}

	result, err := client.DescribeLoadBalancers(context.TODO(), input)
	require.NoError(t, err, "Failed to describe load balancer %s", albArn)
	require.Len(t, result.LoadBalancers, 1, "Expected exactly one load balancer with ARN %s", albArn)

	return result.LoadBalancers[0].State.Code
}

// LoadBalancerExists checks if a load balancer with the given ARN exists.
func LoadBalancerExists(t *testing.T, albArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancersInput{
		LoadBalancerArns: []string{albArn},
	}

	result, err := client.DescribeLoadBalancers(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.LoadBalancers) > 0
}

// SecurityGroupExists checks if a security group with the given ID exists.
func SecurityGroupExists(t *testing.T, securityGroupId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSecurityGroupsInput{
		GroupIds: []string{securityGroupId},
	}

	result, err := client.DescribeSecurityGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.SecurityGroups) > 0
}

// SecurityGroupHasIngressRule checks if a security group has an ingress rule for the specified port.
// It checks for TCP rules that allow traffic on the given port.
func SecurityGroupHasIngressRule(t *testing.T, securityGroupId string, port int32, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSecurityGroupRulesInput{
		Filters: []types.Filter{
			{
				Name:   stringPtr("group-id"),
				Values: []string{securityGroupId},
			},
		},
	}

	result, err := client.DescribeSecurityGroupRules(context.TODO(), input)
	require.NoError(t, err, "Failed to describe security group rules for %s", securityGroupId)

	for _, rule := range result.SecurityGroupRules {
		// Check for ingress rules (not egress)
		if rule.IsEgress != nil && *rule.IsEgress {
			continue
		}

		// Check if the rule allows traffic on the specified port
		if rule.FromPort != nil && rule.ToPort != nil {
			if *rule.FromPort <= port && port <= *rule.ToPort {
				// Check for TCP protocol (-1 means all protocols, 6 is TCP)
				if rule.IpProtocol != nil && (*rule.IpProtocol == "tcp" || *rule.IpProtocol == "-1" || *rule.IpProtocol == "6") {
					return true
				}
			}
		}
	}

	return false
}

// SecurityGroupHasEgressRule checks if a security group has an egress rule for the specified port.
// It checks for TCP rules that allow traffic on the given port.
func SecurityGroupHasEgressRule(t *testing.T, securityGroupId string, port int32, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSecurityGroupRulesInput{
		Filters: []types.Filter{
			{
				Name:   stringPtr("group-id"),
				Values: []string{securityGroupId},
			},
		},
	}

	result, err := client.DescribeSecurityGroupRules(context.TODO(), input)
	require.NoError(t, err, "Failed to describe security group rules for %s", securityGroupId)

	for _, rule := range result.SecurityGroupRules {
		// Check for egress rules only
		if rule.IsEgress == nil || !*rule.IsEgress {
			continue
		}

		// Check if the rule allows traffic on the specified port
		if rule.FromPort != nil && rule.ToPort != nil {
			if *rule.FromPort <= port && port <= *rule.ToPort {
				// Check for TCP protocol (-1 means all protocols, 6 is TCP)
				if rule.IpProtocol != nil && (*rule.IpProtocol == "tcp" || *rule.IpProtocol == "-1" || *rule.IpProtocol == "6") {
					return true
				}
			}
		}
	}

	return false
}

// SecurityGroupHasEgressRuleWithCidr checks if a security group has an egress rule for the specified port and CIDR.
// It checks for TCP rules that allow traffic on the given port to the specified CIDR block.
func SecurityGroupHasEgressRuleWithCidr(t *testing.T, securityGroupId string, port int32, cidr string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSecurityGroupRulesInput{
		Filters: []types.Filter{
			{
				Name:   stringPtr("group-id"),
				Values: []string{securityGroupId},
			},
		},
	}

	result, err := client.DescribeSecurityGroupRules(context.TODO(), input)
	require.NoError(t, err, "Failed to describe security group rules for %s", securityGroupId)

	for _, rule := range result.SecurityGroupRules {
		// Check for egress rules only
		if rule.IsEgress == nil || !*rule.IsEgress {
			continue
		}

		// Check if the rule allows traffic on the specified port
		if rule.FromPort != nil && rule.ToPort != nil {
			if *rule.FromPort <= port && port <= *rule.ToPort {
				// Check for TCP protocol (-1 means all protocols, 6 is TCP)
				if rule.IpProtocol != nil && (*rule.IpProtocol == "tcp" || *rule.IpProtocol == "-1" || *rule.IpProtocol == "6") {
					// Check CIDR matches
					if rule.CidrIpv4 != nil && *rule.CidrIpv4 == cidr {
						return true
					}
				}
			}
		}
	}

	return false
}

// stringPtr returns a pointer to the given string.
func stringPtr(s string) *string {
	return &s
}

// GetListenerProtocol returns the protocol of a listener (HTTP, HTTPS, etc.).
func GetListenerProtocol(t *testing.T, listenerArn string, region string) elbv2types.ProtocolEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener %s", listenerArn)
	require.Len(t, result.Listeners, 1, "Expected exactly one listener with ARN %s", listenerArn)

	return result.Listeners[0].Protocol
}

// GetListenerPort returns the port of a listener.
func GetListenerPort(t *testing.T, listenerArn string, region string) int32 {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener %s", listenerArn)
	require.Len(t, result.Listeners, 1, "Expected exactly one listener with ARN %s", listenerArn)

	if result.Listeners[0].Port != nil {
		return *result.Listeners[0].Port
	}
	return 0
}

// ListenerHasRedirectAction checks if a listener has a redirect action as its default action.
// Returns true if the listener has a redirect action, and the redirect status code and target port.
func ListenerHasRedirectAction(t *testing.T, listenerArn string, region string) (bool, string, string) {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener %s", listenerArn)
	require.Len(t, result.Listeners, 1, "Expected exactly one listener with ARN %s", listenerArn)

	for _, action := range result.Listeners[0].DefaultActions {
		if action.Type == elbv2types.ActionTypeEnumRedirect && action.RedirectConfig != nil {
			statusCode := ""
			port := ""
			if action.RedirectConfig.StatusCode != "" {
				statusCode = string(action.RedirectConfig.StatusCode)
			}
			if action.RedirectConfig.Port != nil {
				port = *action.RedirectConfig.Port
			}
			return true, statusCode, port
		}
	}

	return false, "", ""
}

// ListenerExists checks if a listener with the given ARN exists.
func ListenerExists(t *testing.T, listenerArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.Listeners) > 0
}

// getECSClient creates an ECS client for the specified region.
func getECSClient(t *testing.T, region string) *ecs.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return ecs.NewFromConfig(cfg)
}

// EcsClusterExists checks if an ECS cluster with the given ARN exists.
func EcsClusterExists(t *testing.T, clusterArn string, region string) bool {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	if err != nil {
		return false
	}

	// Check that the cluster exists and is not in INACTIVE status
	for _, cluster := range result.Clusters {
		if cluster.ClusterArn != nil && *cluster.ClusterArn == clusterArn {
			return cluster.Status != nil && *cluster.Status != "INACTIVE"
		}
	}

	return false
}

// GetEcsClusterStatus returns the status of an ECS cluster.
// Common statuses: ACTIVE, PROVISIONING, DEPROVISIONING, FAILED, INACTIVE.
func GetEcsClusterStatus(t *testing.T, clusterArn string, region string) string {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS cluster %s", clusterArn)
	require.Len(t, result.Clusters, 1, "Expected exactly one ECS cluster with ARN %s", clusterArn)

	if result.Clusters[0].Status != nil {
		return *result.Clusters[0].Status
	}
	return ""
}

// GetEcsClusterCapacityProviders returns the list of capacity providers attached to an ECS cluster.
func GetEcsClusterCapacityProviders(t *testing.T, clusterArn string, region string) []string {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS cluster %s", clusterArn)
	require.Len(t, result.Clusters, 1, "Expected exactly one ECS cluster with ARN %s", clusterArn)

	return result.Clusters[0].CapacityProviders
}

// EcsClusterHasCapacityProvider checks if an ECS cluster has a specific capacity provider attached.
func EcsClusterHasCapacityProvider(t *testing.T, clusterArn string, capacityProviderName string, region string) bool {
	capacityProviders := GetEcsClusterCapacityProviders(t, clusterArn, region)

	for _, cp := range capacityProviders {
		if cp == capacityProviderName {
			return true
		}
	}

	return false
}

// GetEcsClusterDefaultCapacityProviderStrategy returns the default capacity provider strategy for a cluster.
func GetEcsClusterDefaultCapacityProviderStrategy(t *testing.T, clusterArn string, region string) []ecstypes.CapacityProviderStrategyItem {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS cluster %s", clusterArn)
	require.Len(t, result.Clusters, 1, "Expected exactly one ECS cluster with ARN %s", clusterArn)

	return result.Clusters[0].DefaultCapacityProviderStrategy
}

// TargetGroupExists checks if a target group with the given ARN exists.
func TargetGroupExists(t *testing.T, targetGroupArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.TargetGroups) > 0
}

// GetTargetGroupTargetType returns the target type of a target group (instance, ip, lambda, alb).
func GetTargetGroupTargetType(t *testing.T, targetGroupArn string, region string) elbv2types.TargetTypeEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	return result.TargetGroups[0].TargetType
}

// GetTargetGroupProtocol returns the protocol of a target group (HTTP, HTTPS, TCP, etc.).
func GetTargetGroupProtocol(t *testing.T, targetGroupArn string, region string) elbv2types.ProtocolEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	return result.TargetGroups[0].Protocol
}

// GetTargetGroupPort returns the port of a target group.
func GetTargetGroupPort(t *testing.T, targetGroupArn string, region string) int32 {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	if result.TargetGroups[0].Port != nil {
		return *result.TargetGroups[0].Port
	}
	return 0
}

// EcsServiceExists checks if an ECS service with the given name exists in the specified cluster.
func EcsServiceExists(t *testing.T, clusterArn string, serviceName string, region string) bool {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	if err != nil {
		return false
	}

	// Check that the service exists and is not in INACTIVE status
	for _, service := range result.Services {
		if service.ServiceName != nil && *service.ServiceName == serviceName {
			return service.Status != nil && *service.Status != "INACTIVE"
		}
	}

	return false
}

// GetEcsServiceStatus returns the status of an ECS service.
// Common statuses: ACTIVE, DRAINING, INACTIVE.
func GetEcsServiceStatus(t *testing.T, clusterArn string, serviceName string, region string) string {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	if result.Services[0].Status != nil {
		return *result.Services[0].Status
	}
	return ""
}

// GetEcsServiceDesiredCount returns the desired count of an ECS service.
func GetEcsServiceDesiredCount(t *testing.T, clusterArn string, serviceName string, region string) int32 {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	return result.Services[0].DesiredCount
}

// GetEcsServiceRunningCount returns the running count of an ECS service.
func GetEcsServiceRunningCount(t *testing.T, clusterArn string, serviceName string, region string) int32 {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	return result.Services[0].RunningCount
}

// WaitForEcsServiceRunningCount waits for an ECS service to reach the expected running count.
// It retries up to maxRetries times with retryInterval seconds between each retry.
// Returns true if the service reached the expected running count, false otherwise.
func WaitForEcsServiceRunningCount(t *testing.T, clusterArn string, serviceName string, expectedCount int32, maxRetries int, retryIntervalSeconds int, region string) bool {
	client := getECSClient(t, region)

	for i := 0; i < maxRetries; i++ {
		input := &ecs.DescribeServicesInput{
			Cluster:  &clusterArn,
			Services: []string{serviceName},
		}

		result, err := client.DescribeServices(context.TODO(), input)
		if err != nil {
			t.Logf("Retry %d/%d: Failed to describe ECS service %s: %v", i+1, maxRetries, serviceName, err)
			continue
		}

		if len(result.Services) == 1 {
			runningCount := result.Services[0].RunningCount
			t.Logf("Retry %d/%d: ECS service %s running count: %d (expected: %d)", i+1, maxRetries, serviceName, runningCount, expectedCount)
			if runningCount == expectedCount {
				return true
			}
		}

		if i < maxRetries-1 {
			t.Logf("Waiting %d seconds before next retry...", retryIntervalSeconds)
			time.Sleep(time.Duration(retryIntervalSeconds) * time.Second)
		}
	}

	return false
}

// GetEcsServiceLoadBalancers returns the load balancer configurations attached to an ECS service.
func GetEcsServiceLoadBalancers(t *testing.T, clusterArn string, serviceName string, region string) []ecstypes.LoadBalancer {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	return result.Services[0].LoadBalancers
}

// EcsServiceHasTargetGroup checks if an ECS service is registered with a specific target group.
func EcsServiceHasTargetGroup(t *testing.T, clusterArn string, serviceName string, targetGroupArn string, region string) bool {
	loadBalancers := GetEcsServiceLoadBalancers(t, clusterArn, serviceName, region)

	for _, lb := range loadBalancers {
		if lb.TargetGroupArn != nil && *lb.TargetGroupArn == targetGroupArn {
			return true
		}
	}

	return false
}

// GetTargetGroupHealthCounts returns the count of healthy and unhealthy targets in a target group.
func GetTargetGroupHealthCounts(t *testing.T, targetGroupArn string, region string) (healthy int, unhealthy int, total int) {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetHealthInput{
		TargetGroupArn: &targetGroupArn,
	}

	result, err := client.DescribeTargetHealth(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target health for target group %s", targetGroupArn)

	for _, targetHealth := range result.TargetHealthDescriptions {
		total++
		if targetHealth.TargetHealth != nil {
			switch targetHealth.TargetHealth.State {
			case elbv2types.TargetHealthStateEnumHealthy:
				healthy++
			case elbv2types.TargetHealthStateEnumUnhealthy:
				unhealthy++
			}
		}
	}

	return healthy, unhealthy, total
}

// WaitForTargetGroupHealthyTargets waits for a target group to have at least minHealthy healthy targets.
// It retries up to maxRetries times with retryInterval seconds between each retry.
// Returns true if the target group has at least minHealthy healthy targets, false otherwise.
func WaitForTargetGroupHealthyTargets(t *testing.T, targetGroupArn string, minHealthy int, maxRetries int, retryIntervalSeconds int, region string) bool {
	for i := 0; i < maxRetries; i++ {
		healthy, unhealthy, total := GetTargetGroupHealthCounts(t, targetGroupArn, region)
		t.Logf("Retry %d/%d: Target group has %d healthy, %d unhealthy, %d total targets (need at least %d healthy)",
			i+1, maxRetries, healthy, unhealthy, total, minHealthy)

		if healthy >= minHealthy {
			return true
		}

		if i < maxRetries-1 {
			t.Logf("Waiting %d seconds before next retry...", retryIntervalSeconds)
			time.Sleep(time.Duration(retryIntervalSeconds) * time.Second)
		}
	}

	return false
}

// TargetGroupHasRegisteredTargets checks if a target group has any registered targets.
func TargetGroupHasRegisteredTargets(t *testing.T, targetGroupArn string, region string) bool {
	_, _, total := GetTargetGroupHealthCounts(t, targetGroupArn, region)
	return total > 0
}

// getElastiCacheClient creates an ElastiCache client for the specified region.
func getElastiCacheClient(t *testing.T, region string) *elasticache.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return elasticache.NewFromConfig(cfg)
}

// ElastiCacheReplicationGroupExists checks if an ElastiCache replication group with the given ID exists.
func ElastiCacheReplicationGroupExists(t *testing.T, replicationGroupId string, region string) bool {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeReplicationGroupsInput{
		ReplicationGroupId: &replicationGroupId,
	}

	result, err := client.DescribeReplicationGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.ReplicationGroups) > 0
}

// GetElastiCacheReplicationGroupStatus returns the status of an ElastiCache replication group.
// Common statuses: creating, available, modifying, deleting, create-failed, snapshotting.
func GetElastiCacheReplicationGroupStatus(t *testing.T, replicationGroupId string, region string) string {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeReplicationGroupsInput{
		ReplicationGroupId: &replicationGroupId,
	}

	result, err := client.DescribeReplicationGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache replication group %s", replicationGroupId)
	require.Len(t, result.ReplicationGroups, 1, "Expected exactly one replication group with ID %s", replicationGroupId)

	if result.ReplicationGroups[0].Status != nil {
		return *result.ReplicationGroups[0].Status
	}
	return ""
}

// GetRouteTableNatGatewayId returns the NAT Gateway ID from a route table's default route (0.0.0.0/0).
// Returns an empty string if no NAT Gateway route is found.
func GetRouteTableNatGatewayId(t *testing.T, routeTableId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeRouteTablesInput{
		RouteTableIds: []string{routeTableId},
	}

	result, err := client.DescribeRouteTables(context.TODO(), input)
	require.NoError(t, err, "Failed to describe route table %s", routeTableId)
	require.Len(t, result.RouteTables, 1, "Expected exactly one route table with ID %s", routeTableId)

	for _, route := range result.RouteTables[0].Routes {
		// Check for default route (0.0.0.0/0) pointing to a NAT Gateway
		if route.DestinationCidrBlock != nil && *route.DestinationCidrBlock == "0.0.0.0/0" {
			if route.NatGatewayId != nil && *route.NatGatewayId != "" {
				return *route.NatGatewayId
			}
		}
	}

	return ""
}

// GetVpcIpv6CidrBlock returns the IPv6 CIDR block for the specified VPC.
// Returns an empty string if the VPC has no IPv6 CIDR block.
func GetVpcIpv6CidrBlock(t *testing.T, vpcId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC %s", vpcId)
	require.Len(t, result.Vpcs, 1, "Expected exactly one VPC with ID %s", vpcId)

	vpc := result.Vpcs[0]
	for _, cidrBlock := range vpc.Ipv6CidrBlockAssociationSet {
		if cidrBlock.Ipv6CidrBlock != nil && cidrBlock.Ipv6CidrBlockState != nil {
			if cidrBlock.Ipv6CidrBlockState.State == types.VpcCidrBlockStateCodeAssociated {
				return *cidrBlock.Ipv6CidrBlock
			}
		}
	}

	return ""
}

// VpcHasIpv6CidrBlock checks if a VPC has an IPv6 CIDR block assigned.
func VpcHasIpv6CidrBlock(t *testing.T, vpcId string, region string) bool {
	return GetVpcIpv6CidrBlock(t, vpcId, region) != ""
}

// EgressOnlyInternetGatewayExists checks if an egress-only internet gateway with the given ID exists.
func EgressOnlyInternetGatewayExists(t *testing.T, eigwId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeEgressOnlyInternetGatewaysInput{
		EgressOnlyInternetGatewayIds: []string{eigwId},
	}

	result, err := client.DescribeEgressOnlyInternetGateways(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.EgressOnlyInternetGateways) > 0
}

// GetSubnetIpv6CidrBlock returns the IPv6 CIDR block for the specified subnet.
// Returns an empty string if the subnet has no IPv6 CIDR block.
func GetSubnetIpv6CidrBlock(t *testing.T, subnetId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSubnetsInput{
		SubnetIds: []string{subnetId},
	}

	result, err := client.DescribeSubnets(context.TODO(), input)
	require.NoError(t, err, "Failed to describe subnet %s", subnetId)
	require.Len(t, result.Subnets, 1, "Expected exactly one subnet with ID %s", subnetId)

	subnet := result.Subnets[0]
	for _, cidrBlock := range subnet.Ipv6CidrBlockAssociationSet {
		if cidrBlock.Ipv6CidrBlock != nil && cidrBlock.Ipv6CidrBlockState != nil {
			if cidrBlock.Ipv6CidrBlockState.State == types.SubnetCidrBlockStateCodeAssociated {
				return *cidrBlock.Ipv6CidrBlock
			}
		}
	}

	return ""
}

// SubnetHasIpv6CidrBlock checks if a subnet has an IPv6 CIDR block assigned.
func SubnetHasIpv6CidrBlock(t *testing.T, subnetId string, region string) bool {
	return GetSubnetIpv6CidrBlock(t, subnetId, region) != ""
}

// GetLoadBalancerCrossZoneEnabled checks if cross-zone load balancing is enabled for a load balancer.
// Returns true if the load_balancing.cross_zone.enabled attribute is "true".
func GetLoadBalancerCrossZoneEnabled(t *testing.T, lbArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancerAttributesInput{
		LoadBalancerArn: &lbArn,
	}

	result, err := client.DescribeLoadBalancerAttributes(context.TODO(), input)
	require.NoError(t, err, "Failed to describe load balancer attributes for %s", lbArn)

	for _, attr := range result.Attributes {
		if attr.Key != nil && *attr.Key == "load_balancing.cross_zone.enabled" {
			if attr.Value != nil {
				return *attr.Value == "true"
			}
		}
	}

	return false
}

// getCloudWatchLogsClient creates a CloudWatch Logs client for the specified region.
func getCloudWatchLogsClient(t *testing.T, region string) *cloudwatchlogs.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return cloudwatchlogs.NewFromConfig(cfg)
}

// CloudWatchLogGroupExists checks if a CloudWatch log group with the given name exists.
func CloudWatchLogGroupExists(t *testing.T, logGroupName string, region string) bool {
	client := getCloudWatchLogsClient(t, region)

	input := &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: &logGroupName,
	}

	result, err := client.DescribeLogGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	// Check for exact match since we're using prefix
	for _, logGroup := range result.LogGroups {
		if logGroup.LogGroupName != nil && *logGroup.LogGroupName == logGroupName {
			return true
		}
	}

	return false
}

// GetCloudWatchLogGroupArn returns the ARN of a CloudWatch log group.
// Returns an empty string if the log group doesn't exist.
func GetCloudWatchLogGroupArn(t *testing.T, logGroupName string, region string) string {
	client := getCloudWatchLogsClient(t, region)

	input := &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: &logGroupName,
	}

	result, err := client.DescribeLogGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe CloudWatch log groups")

	// Check for exact match since we're using prefix
	for _, logGroup := range result.LogGroups {
		if logGroup.LogGroupName != nil && *logGroup.LogGroupName == logGroupName {
			if logGroup.Arn != nil {
				return *logGroup.Arn
			}
		}
	}

	return ""
}

// VpcFlowLogExists checks if a VPC flow log with the given ID exists.
func VpcFlowLogExists(t *testing.T, flowLogId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeFlowLogsInput{
		FlowLogIds: []string{flowLogId},
	}

	result, err := client.DescribeFlowLogs(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.FlowLogs) > 0
}

// GetVpcFlowLogStatus returns the status of a VPC flow log (ACTIVE or inactive).
func GetVpcFlowLogStatus(t *testing.T, flowLogId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeFlowLogsInput{
		FlowLogIds: []string{flowLogId},
	}

	result, err := client.DescribeFlowLogs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC flow log %s", flowLogId)
	require.Len(t, result.FlowLogs, 1, "Expected exactly one flow log with ID %s", flowLogId)

	if result.FlowLogs[0].FlowLogStatus != nil {
		return *result.FlowLogs[0].FlowLogStatus
	}
	return ""
}

// GetVpcFlowLogDestination returns the destination of a VPC flow log.
// For CloudWatch Logs, this returns the log group ARN.
// For S3, this returns the S3 bucket ARN.
func GetVpcFlowLogDestination(t *testing.T, flowLogId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeFlowLogsInput{
		FlowLogIds: []string{flowLogId},
	}

	result, err := client.DescribeFlowLogs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC flow log %s", flowLogId)
	require.Len(t, result.FlowLogs, 1, "Expected exactly one flow log with ID %s", flowLogId)

	if result.FlowLogs[0].LogDestination != nil {
		return *result.FlowLogs[0].LogDestination
	}
	// For CloudWatch Logs, also check LogGroupName
	if result.FlowLogs[0].LogGroupName != nil {
		return *result.FlowLogs[0].LogGroupName
	}
	return ""
}

// GetVpcFlowLogDestinationType returns the destination type of a VPC flow log.
// Returns "cloud-watch-logs" or "s3".
func GetVpcFlowLogDestinationType(t *testing.T, flowLogId string, region string) types.LogDestinationType {
	client := getEC2Client(t, region)

	input := &ec2.DescribeFlowLogsInput{
		FlowLogIds: []string{flowLogId},
	}

	result, err := client.DescribeFlowLogs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC flow log %s", flowLogId)
	require.Len(t, result.FlowLogs, 1, "Expected exactly one flow log with ID %s", flowLogId)

	return result.FlowLogs[0].LogDestinationType
}

// VpcFlowLogIsAttachedToVpc checks if a flow log is attached to the specified VPC.
func VpcFlowLogIsAttachedToVpc(t *testing.T, flowLogId string, vpcId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeFlowLogsInput{
		FlowLogIds: []string{flowLogId},
	}

	result, err := client.DescribeFlowLogs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC flow log %s", flowLogId)
	require.Len(t, result.FlowLogs, 1, "Expected exactly one flow log with ID %s", flowLogId)

	if result.FlowLogs[0].ResourceId != nil {
		return *result.FlowLogs[0].ResourceId == vpcId
	}
	return false
}

// getApplicationAutoScalingClient creates an Application Auto Scaling client for the specified region.
func getApplicationAutoScalingClient(t *testing.T, region string) *applicationautoscaling.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return applicationautoscaling.NewFromConfig(cfg)
}

// AppAutoScalingTargetExists checks if an Application Auto Scaling target exists for the given resource.
// resourceId should be in the format "service/{cluster-name}/{service-name}" for ECS services.
func AppAutoScalingTargetExists(t *testing.T, resourceId string, region string) bool {
	client := getApplicationAutoScalingClient(t, region)

	input := &applicationautoscaling.DescribeScalableTargetsInput{
		ServiceNamespace: applicationautoscalingtypes.ServiceNamespaceEcs,
		ResourceIds:      []string{resourceId},
	}

	result, err := client.DescribeScalableTargets(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.ScalableTargets) > 0
}

// GetAppAutoScalingTargetMinCapacity returns the minimum capacity of an Application Auto Scaling target.
// resourceId should be in the format "service/{cluster-name}/{service-name}" for ECS services.
func GetAppAutoScalingTargetMinCapacity(t *testing.T, resourceId string, region string) int32 {
	client := getApplicationAutoScalingClient(t, region)

	input := &applicationautoscaling.DescribeScalableTargetsInput{
		ServiceNamespace: applicationautoscalingtypes.ServiceNamespaceEcs,
		ResourceIds:      []string{resourceId},
	}

	result, err := client.DescribeScalableTargets(context.TODO(), input)
	require.NoError(t, err, "Failed to describe scalable target %s", resourceId)
	require.Len(t, result.ScalableTargets, 1, "Expected exactly one scalable target with resource ID %s", resourceId)

	if result.ScalableTargets[0].MinCapacity != nil {
		return *result.ScalableTargets[0].MinCapacity
	}
	return 0
}

// GetAppAutoScalingTargetMaxCapacity returns the maximum capacity of an Application Auto Scaling target.
// resourceId should be in the format "service/{cluster-name}/{service-name}" for ECS services.
func GetAppAutoScalingTargetMaxCapacity(t *testing.T, resourceId string, region string) int32 {
	client := getApplicationAutoScalingClient(t, region)

	input := &applicationautoscaling.DescribeScalableTargetsInput{
		ServiceNamespace: applicationautoscalingtypes.ServiceNamespaceEcs,
		ResourceIds:      []string{resourceId},
	}

	result, err := client.DescribeScalableTargets(context.TODO(), input)
	require.NoError(t, err, "Failed to describe scalable target %s", resourceId)
	require.Len(t, result.ScalableTargets, 1, "Expected exactly one scalable target with resource ID %s", resourceId)

	if result.ScalableTargets[0].MaxCapacity != nil {
		return *result.ScalableTargets[0].MaxCapacity
	}
	return 0
}

// GetAppAutoScalingPolicies returns the scaling policies for an Application Auto Scaling target.
// resourceId should be in the format "service/{cluster-name}/{service-name}" for ECS services.
func GetAppAutoScalingPolicies(t *testing.T, resourceId string, region string) []applicationautoscalingtypes.ScalingPolicy {
	client := getApplicationAutoScalingClient(t, region)

	input := &applicationautoscaling.DescribeScalingPoliciesInput{
		ServiceNamespace: applicationautoscalingtypes.ServiceNamespaceEcs,
		ResourceId:       &resourceId,
	}

	result, err := client.DescribeScalingPolicies(context.TODO(), input)
	require.NoError(t, err, "Failed to describe scaling policies for %s", resourceId)

	return result.ScalingPolicies
}

// AppAutoScalingPolicyExists checks if a scaling policy with the given name exists for a resource.
// resourceId should be in the format "service/{cluster-name}/{service-name}" for ECS services.
func AppAutoScalingPolicyExists(t *testing.T, resourceId string, policyName string, region string) bool {
	policies := GetAppAutoScalingPolicies(t, resourceId, region)

	for _, policy := range policies {
		if policy.PolicyName != nil && *policy.PolicyName == policyName {
			return true
		}
	}

	return false
}

// GetAppAutoScalingPolicyCount returns the number of scaling policies for an Application Auto Scaling target.
// resourceId should be in the format "service/{cluster-name}/{service-name}" for ECS services.
func GetAppAutoScalingPolicyCount(t *testing.T, resourceId string, region string) int {
	policies := GetAppAutoScalingPolicies(t, resourceId, region)
	return len(policies)
}

// GetEcsServiceAutoScalingResourceId constructs the Application Auto Scaling resource ID
// from a cluster ARN and service name.
// Returns a resource ID in the format "service/{cluster-name}/{service-name}".
func GetEcsServiceAutoScalingResourceId(clusterArn string, serviceName string) string {
	// Extract cluster name from ARN (format: arn:aws:ecs:region:account:cluster/cluster-name)
	clusterName := ""
	for i := len(clusterArn) - 1; i >= 0; i-- {
		if clusterArn[i] == '/' {
			clusterName = clusterArn[i+1:]
			break
		}
	}
	return "service/" + clusterName + "/" + serviceName
}

// ElastiCacheClusterExists checks if an ElastiCache cluster (Memcached) with the given ID exists.
func ElastiCacheClusterExists(t *testing.T, clusterId string, region string) bool {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeCacheClustersInput{
		CacheClusterId: &clusterId,
	}

	result, err := client.DescribeCacheClusters(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.CacheClusters) > 0
}

// GetElastiCacheClusterStatus returns the status of an ElastiCache cluster (Memcached).
// Common statuses: creating, available, modifying, deleting, create-failed, snapshotting.
func GetElastiCacheClusterStatus(t *testing.T, clusterId string, region string) string {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeCacheClustersInput{
		CacheClusterId: &clusterId,
	}

	result, err := client.DescribeCacheClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache cluster %s", clusterId)
	require.Len(t, result.CacheClusters, 1, "Expected exactly one cluster with ID %s", clusterId)

	if result.CacheClusters[0].CacheClusterStatus != nil {
		return *result.CacheClusters[0].CacheClusterStatus
	}
	return ""
}

// GetElastiCacheClusterEngine returns the engine type of an ElastiCache cluster.
// Returns "memcached" for Memcached clusters.
func GetElastiCacheClusterEngine(t *testing.T, clusterId string, region string) string {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeCacheClustersInput{
		CacheClusterId: &clusterId,
	}

	result, err := client.DescribeCacheClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache cluster %s", clusterId)
	require.Len(t, result.CacheClusters, 1, "Expected exactly one cluster with ID %s", clusterId)

	if result.CacheClusters[0].Engine != nil {
		return *result.CacheClusters[0].Engine
	}
	return ""
}

// GetElastiCacheClusterNumCacheNodes returns the number of cache nodes in an ElastiCache cluster.
func GetElastiCacheClusterNumCacheNodes(t *testing.T, clusterId string, region string) int32 {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeCacheClustersInput{
		CacheClusterId: &clusterId,
	}

	result, err := client.DescribeCacheClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache cluster %s", clusterId)
	require.Len(t, result.CacheClusters, 1, "Expected exactly one cluster with ID %s", clusterId)

	if result.CacheClusters[0].NumCacheNodes != nil {
		return *result.CacheClusters[0].NumCacheNodes
	}
	return 0
}

// GetElastiCacheReplicationGroupMemberClusters returns the list of member cluster IDs in a replication group.
func GetElastiCacheReplicationGroupMemberClusters(t *testing.T, replicationGroupId string, region string) []string {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeReplicationGroupsInput{
		ReplicationGroupId: &replicationGroupId,
	}

	result, err := client.DescribeReplicationGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache replication group %s", replicationGroupId)
	require.Len(t, result.ReplicationGroups, 1, "Expected exactly one replication group with ID %s", replicationGroupId)

	return result.ReplicationGroups[0].MemberClusters
}

// GetElastiCacheReplicationGroupMemberClusterCount returns the number of member clusters in a replication group.
func GetElastiCacheReplicationGroupMemberClusterCount(t *testing.T, replicationGroupId string, region string) int {
	members := GetElastiCacheReplicationGroupMemberClusters(t, replicationGroupId, region)
	return len(members)
}

// GetElastiCacheReplicationGroupNodeGroups returns the list of node groups in a replication group.
// For non-cluster mode, there will be 1 node group with multiple nodes (primary + replicas).
// For cluster mode, there will be multiple node groups (shards).
func GetElastiCacheReplicationGroupNodeGroups(t *testing.T, replicationGroupId string, region string) []NodeGroupInfo {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeReplicationGroupsInput{
		ReplicationGroupId: &replicationGroupId,
	}

	result, err := client.DescribeReplicationGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache replication group %s", replicationGroupId)
	require.Len(t, result.ReplicationGroups, 1, "Expected exactly one replication group with ID %s", replicationGroupId)

	var nodeGroups []NodeGroupInfo
	for _, ng := range result.ReplicationGroups[0].NodeGroups {
		nodeGroup := NodeGroupInfo{
			NodeGroupId: "",
			Status:      "",
			Slots:       "",
		}
		if ng.NodeGroupId != nil {
			nodeGroup.NodeGroupId = *ng.NodeGroupId
		}
		if ng.Status != nil {
			nodeGroup.Status = *ng.Status
		}
		if ng.Slots != nil {
			nodeGroup.Slots = *ng.Slots
		}

		// Get node members
		for _, member := range ng.NodeGroupMembers {
			nodeMember := NodeMemberInfo{
				CacheClusterId:            "",
				CacheNodeId:               "",
				CurrentRole:               "",
				PreferredAvailabilityZone: "",
			}
			if member.CacheClusterId != nil {
				nodeMember.CacheClusterId = *member.CacheClusterId
			}
			if member.CacheNodeId != nil {
				nodeMember.CacheNodeId = *member.CacheNodeId
			}
			if member.CurrentRole != nil {
				nodeMember.CurrentRole = *member.CurrentRole
			}
			if member.PreferredAvailabilityZone != nil {
				nodeMember.PreferredAvailabilityZone = *member.PreferredAvailabilityZone
			}
			nodeGroup.NodeMembers = append(nodeGroup.NodeMembers, nodeMember)
		}

		nodeGroups = append(nodeGroups, nodeGroup)
	}

	return nodeGroups
}

// NodeGroupInfo represents information about a node group in a replication group.
type NodeGroupInfo struct {
	NodeGroupId string
	Status      string
	Slots       string
	NodeMembers []NodeMemberInfo
}

// NodeMemberInfo represents information about a node member in a node group.
type NodeMemberInfo struct {
	CacheClusterId            string
	CacheNodeId               string
	CurrentRole               string
	PreferredAvailabilityZone string
}

// GetElastiCacheReplicationGroupNodeCount returns the total number of nodes across all node groups.
// This includes both primary and replica nodes.
func GetElastiCacheReplicationGroupNodeCount(t *testing.T, replicationGroupId string, region string) int {
	nodeGroups := GetElastiCacheReplicationGroupNodeGroups(t, replicationGroupId, region)
	total := 0
	for _, ng := range nodeGroups {
		total += len(ng.NodeMembers)
	}
	return total
}

// GetElastiCacheReplicationGroupPrimaryCount returns the number of primary nodes in a replication group.
func GetElastiCacheReplicationGroupPrimaryCount(t *testing.T, replicationGroupId string, region string) int {
	nodeGroups := GetElastiCacheReplicationGroupNodeGroups(t, replicationGroupId, region)
	count := 0
	for _, ng := range nodeGroups {
		for _, member := range ng.NodeMembers {
			if member.CurrentRole == "primary" {
				count++
			}
		}
	}
	return count
}

// GetElastiCacheReplicationGroupReplicaCount returns the number of replica nodes in a replication group.
func GetElastiCacheReplicationGroupReplicaCount(t *testing.T, replicationGroupId string, region string) int {
	nodeGroups := GetElastiCacheReplicationGroupNodeGroups(t, replicationGroupId, region)
	count := 0
	for _, ng := range nodeGroups {
		for _, member := range ng.NodeMembers {
			if member.CurrentRole == "replica" {
				count++
			}
		}
	}
	return count
}

// AllElastiCacheReplicationGroupMembersAvailable checks if all member clusters in a replication group are available.
func AllElastiCacheReplicationGroupMembersAvailable(t *testing.T, replicationGroupId string, region string) bool {
	members := GetElastiCacheReplicationGroupMemberClusters(t, replicationGroupId, region)
	if len(members) == 0 {
		return false
	}

	for _, memberId := range members {
		status := GetElastiCacheClusterStatus(t, memberId, region)
		if status != "available" {
			return false
		}
	}

	return true
}

// getWAFv2Client creates a WAFv2 client for the specified region.
func getWAFv2Client(t *testing.T, region string) *wafv2.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return wafv2.NewFromConfig(cfg)
}

// WafWebAclExists checks if a WAFv2 WebACL with the given ARN exists.
// Uses the ARN to determine the scope (REGIONAL for ALB/API Gateway, CLOUDFRONT for CloudFront).
func WafWebAclExists(t *testing.T, webAclArn string, region string) bool {
	client := getWAFv2Client(t, region)

	// Extract the WebACL ID and name from the ARN
	// ARN format: arn:aws:wafv2:{region}:{account}:regional/webacl/{name}/{id}
	name, id := parseWebAclArn(webAclArn)
	if name == "" || id == "" {
		return false
	}

	input := &wafv2.GetWebACLInput{
		Name:  &name,
		Id:    &id,
		Scope: wafv2types.ScopeRegional, // ALB uses REGIONAL scope
	}

	_, err := client.GetWebACL(context.TODO(), input)
	return err == nil
}

// GetWafWebAclName returns the name of a WAFv2 WebACL.
func GetWafWebAclName(t *testing.T, webAclArn string, region string) string {
	client := getWAFv2Client(t, region)

	name, id := parseWebAclArn(webAclArn)
	require.NotEmpty(t, name, "Failed to parse WebACL name from ARN %s", webAclArn)
	require.NotEmpty(t, id, "Failed to parse WebACL ID from ARN %s", webAclArn)

	input := &wafv2.GetWebACLInput{
		Name:  &name,
		Id:    &id,
		Scope: wafv2types.ScopeRegional,
	}

	result, err := client.GetWebACL(context.TODO(), input)
	require.NoError(t, err, "Failed to get WAFv2 WebACL %s", webAclArn)

	if result.WebACL != nil && result.WebACL.Name != nil {
		return *result.WebACL.Name
	}
	return ""
}

// GetWafWebAclRuleCount returns the number of rules in a WAFv2 WebACL.
func GetWafWebAclRuleCount(t *testing.T, webAclArn string, region string) int {
	client := getWAFv2Client(t, region)

	name, id := parseWebAclArn(webAclArn)
	require.NotEmpty(t, name, "Failed to parse WebACL name from ARN %s", webAclArn)
	require.NotEmpty(t, id, "Failed to parse WebACL ID from ARN %s", webAclArn)

	input := &wafv2.GetWebACLInput{
		Name:  &name,
		Id:    &id,
		Scope: wafv2types.ScopeRegional,
	}

	result, err := client.GetWebACL(context.TODO(), input)
	require.NoError(t, err, "Failed to get WAFv2 WebACL %s", webAclArn)

	if result.WebACL != nil {
		return len(result.WebACL.Rules)
	}
	return 0
}

// WafWebAclHasManagedRuleGroup checks if a WAFv2 WebACL contains a specific AWS managed rule group.
func WafWebAclHasManagedRuleGroup(t *testing.T, webAclArn string, ruleGroupName string, region string) bool {
	client := getWAFv2Client(t, region)

	name, id := parseWebAclArn(webAclArn)
	require.NotEmpty(t, name, "Failed to parse WebACL name from ARN %s", webAclArn)
	require.NotEmpty(t, id, "Failed to parse WebACL ID from ARN %s", webAclArn)

	input := &wafv2.GetWebACLInput{
		Name:  &name,
		Id:    &id,
		Scope: wafv2types.ScopeRegional,
	}

	result, err := client.GetWebACL(context.TODO(), input)
	require.NoError(t, err, "Failed to get WAFv2 WebACL %s", webAclArn)

	if result.WebACL != nil {
		for _, rule := range result.WebACL.Rules {
			if rule.Statement != nil && rule.Statement.ManagedRuleGroupStatement != nil {
				if rule.Statement.ManagedRuleGroupStatement.Name != nil {
					if *rule.Statement.ManagedRuleGroupStatement.Name == ruleGroupName {
						return true
					}
				}
			}
		}
	}
	return false
}

// WafWebAclIsAssociatedWithResource checks if a WAFv2 WebACL is associated with a specific resource (e.g., ALB).
func WafWebAclIsAssociatedWithResource(t *testing.T, webAclArn string, resourceArn string, region string) bool {
	client := getWAFv2Client(t, region)

	input := &wafv2.GetWebACLForResourceInput{
		ResourceArn: &resourceArn,
	}

	result, err := client.GetWebACLForResource(context.TODO(), input)
	if err != nil {
		return false
	}

	if result.WebACL != nil && result.WebACL.ARN != nil {
		return *result.WebACL.ARN == webAclArn
	}
	return false
}

// GetWafWebAclForResource returns the ARN of the WebACL associated with a resource.
// Returns an empty string if no WebACL is associated.
func GetWafWebAclForResource(t *testing.T, resourceArn string, region string) string {
	client := getWAFv2Client(t, region)

	input := &wafv2.GetWebACLForResourceInput{
		ResourceArn: &resourceArn,
	}

	result, err := client.GetWebACLForResource(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.WebACL != nil && result.WebACL.ARN != nil {
		return *result.WebACL.ARN
	}
	return ""
}

// parseWebAclArn parses a WebACL ARN and returns the name and ID.
// ARN format: arn:aws:wafv2:{region}:{account}:regional/webacl/{name}/{id}
func parseWebAclArn(arn string) (name string, id string) {
	// Split by "/" to get parts
	parts := make([]string, 0)
	current := ""
	for _, c := range arn {
		if c == '/' {
			if current != "" {
				parts = append(parts, current)
				current = ""
			}
		} else {
			current += string(c)
		}
	}
	if current != "" {
		parts = append(parts, current)
	}

	// Expected format after splitting: [..., "webacl", "{name}", "{id}"]
	// We need the last two parts
	if len(parts) >= 2 {
		id = parts[len(parts)-1]
		name = parts[len(parts)-2]
		return name, id
	}
	return "", ""
}

// getS3Client creates an S3 client for the specified region.
func getS3Client(t *testing.T, region string) *s3.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return s3.NewFromConfig(cfg)
}

// S3BucketExists checks if an S3 bucket with the given name exists.
func S3BucketExists(t *testing.T, bucketName string, region string) bool {
	client := getS3Client(t, region)

	input := &s3.HeadBucketInput{
		Bucket: &bucketName,
	}

	_, err := client.HeadBucket(context.TODO(), input)
	return err == nil
}

// GetS3BucketEncryption returns the server-side encryption configuration for an S3 bucket.
// Returns the encryption algorithm (AES256 or aws:kms) and KMS key ID if applicable.
func GetS3BucketEncryption(t *testing.T, bucketName string, region string) (algorithm string, kmsKeyId string) {
	client := getS3Client(t, region)

	input := &s3.GetBucketEncryptionInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketEncryption(context.TODO(), input)
	require.NoError(t, err, "Failed to get bucket encryption for %s", bucketName)

	if result.ServerSideEncryptionConfiguration != nil {
		for _, rule := range result.ServerSideEncryptionConfiguration.Rules {
			if rule.ApplyServerSideEncryptionByDefault != nil {
				algorithm = string(rule.ApplyServerSideEncryptionByDefault.SSEAlgorithm)
				if rule.ApplyServerSideEncryptionByDefault.KMSMasterKeyID != nil {
					kmsKeyId = *rule.ApplyServerSideEncryptionByDefault.KMSMasterKeyID
				}
				return algorithm, kmsKeyId
			}
		}
	}

	return "", ""
}

// S3BucketHasSSEEncryption checks if an S3 bucket has server-side encryption enabled.
// Returns true if AES256 or aws:kms encryption is enabled.
func S3BucketHasSSEEncryption(t *testing.T, bucketName string, region string) bool {
	algorithm, _ := GetS3BucketEncryption(t, bucketName, region)
	return algorithm == string(s3types.ServerSideEncryptionAes256) || algorithm == string(s3types.ServerSideEncryptionAwsKms)
}

// GetS3BucketPublicAccessBlock returns the public access block configuration for an S3 bucket.
func GetS3BucketPublicAccessBlock(t *testing.T, bucketName string, region string) *s3types.PublicAccessBlockConfiguration {
	client := getS3Client(t, region)

	input := &s3.GetPublicAccessBlockInput{
		Bucket: &bucketName,
	}

	result, err := client.GetPublicAccessBlock(context.TODO(), input)
	require.NoError(t, err, "Failed to get public access block for %s", bucketName)

	return result.PublicAccessBlockConfiguration
}

// S3BucketHasPublicAccessBlocked checks if an S3 bucket has all public access blocked.
// Returns true if all four public access block settings are enabled.
func S3BucketHasPublicAccessBlocked(t *testing.T, bucketName string, region string) bool {
	config := GetS3BucketPublicAccessBlock(t, bucketName, region)
	if config == nil {
		return false
	}

	return config.BlockPublicAcls != nil && *config.BlockPublicAcls &&
		config.BlockPublicPolicy != nil && *config.BlockPublicPolicy &&
		config.IgnorePublicAcls != nil && *config.IgnorePublicAcls &&
		config.RestrictPublicBuckets != nil && *config.RestrictPublicBuckets
}

// GetS3BucketLifecycleRules returns the lifecycle rules for an S3 bucket.
func GetS3BucketLifecycleRules(t *testing.T, bucketName string, region string) []s3types.LifecycleRule {
	client := getS3Client(t, region)

	input := &s3.GetBucketLifecycleConfigurationInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketLifecycleConfiguration(context.TODO(), input)
	require.NoError(t, err, "Failed to get bucket lifecycle configuration for %s", bucketName)

	return result.Rules
}

// S3BucketHasExpirationRule checks if an S3 bucket has a lifecycle rule with expiration.
// If expectedDays > 0, also checks that the expiration days match.
func S3BucketHasExpirationRule(t *testing.T, bucketName string, expectedDays int32, region string) bool {
	rules := GetS3BucketLifecycleRules(t, bucketName, region)

	for _, rule := range rules {
		if rule.Status == s3types.ExpirationStatusEnabled && rule.Expiration != nil {
			if expectedDays <= 0 {
				return true
			}
			if rule.Expiration.Days != nil && *rule.Expiration.Days == expectedDays {
				return true
			}
		}
	}

	return false
}

// S3BucketHasTransitionRule checks if an S3 bucket has a lifecycle rule with a specific transition.
// ruleId: the ID of the rule to check (can be empty string to match any rule)
// storageClass: the target storage class (e.g., "STANDARD_IA", "GLACIER", "DEEP_ARCHIVE")
// days: the number of days after object creation for the transition (0 to match any)
// Returns true if a matching transition rule is found.
func S3BucketHasTransitionRule(t *testing.T, bucketName string, ruleId string, storageClass string, days int32, region string) bool {
	client := getS3Client(t, region)

	input := &s3.GetBucketLifecycleConfigurationInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketLifecycleConfiguration(context.TODO(), input)
	if err != nil {
		// No lifecycle configuration means no transition rules
		return false
	}

	for _, rule := range result.Rules {
		// Skip if ruleId is specified and doesn't match
		if ruleId != "" && (rule.ID == nil || *rule.ID != ruleId) {
			continue
		}

		// Check if the rule is enabled
		if rule.Status != s3types.ExpirationStatusEnabled {
			continue
		}

		// Check transitions
		for _, transition := range rule.Transitions {
			// Check storage class matches
			if string(transition.StorageClass) != storageClass {
				continue
			}

			// If days is 0, match any days value
			if days == 0 {
				return true
			}

			// Check days matches
			if transition.Days != nil && *transition.Days == days {
				return true
			}
		}
	}

	return false
}

// S3BucketHasNoncurrentVersionExpiration checks if an S3 bucket has a lifecycle rule
// that expires noncurrent object versions.
// ruleId: the ID of the rule to check (can be empty string to match any rule)
// days: the number of days after an object version becomes noncurrent (0 to match any)
// Returns true if a matching noncurrent version expiration rule is found.
func S3BucketHasNoncurrentVersionExpiration(t *testing.T, bucketName string, ruleId string, days int32, region string) bool {
	client := getS3Client(t, region)

	input := &s3.GetBucketLifecycleConfigurationInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketLifecycleConfiguration(context.TODO(), input)
	if err != nil {
		// No lifecycle configuration means no noncurrent version expiration rules
		return false
	}

	for _, rule := range result.Rules {
		// Skip if ruleId is specified and doesn't match
		if ruleId != "" && (rule.ID == nil || *rule.ID != ruleId) {
			continue
		}

		// Check if the rule is enabled
		if rule.Status != s3types.ExpirationStatusEnabled {
			continue
		}

		// Check noncurrent version expiration
		if rule.NoncurrentVersionExpiration != nil {
			// If days is 0, match any days value
			if days == 0 {
				return true
			}

			// Check days matches
			if rule.NoncurrentVersionExpiration.NoncurrentDays != nil && *rule.NoncurrentVersionExpiration.NoncurrentDays == days {
				return true
			}
		}
	}

	return false
}

// S3BucketHasAbortMultipartUploadRule checks if an S3 bucket has a lifecycle rule
// that aborts incomplete multipart uploads.
// ruleId: the ID of the rule to check (can be empty string to match any rule)
// days: the number of days after initiation to abort incomplete multipart uploads (0 to match any)
// Returns true if a matching abort multipart upload rule is found.
func S3BucketHasAbortMultipartUploadRule(t *testing.T, bucketName string, ruleId string, days int32, region string) bool {
	client := getS3Client(t, region)

	input := &s3.GetBucketLifecycleConfigurationInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketLifecycleConfiguration(context.TODO(), input)
	if err != nil {
		// No lifecycle configuration means no abort multipart upload rules
		return false
	}

	for _, rule := range result.Rules {
		// Skip if ruleId is specified and doesn't match
		if ruleId != "" && (rule.ID == nil || *rule.ID != ruleId) {
			continue
		}

		// Check if the rule is enabled
		if rule.Status != s3types.ExpirationStatusEnabled {
			continue
		}

		// Check abort incomplete multipart upload
		if rule.AbortIncompleteMultipartUpload != nil {
			// If days is 0, match any days value
			if days == 0 {
				return true
			}

			// Check days matches
			if rule.AbortIncompleteMultipartUpload.DaysAfterInitiation != nil && *rule.AbortIncompleteMultipartUpload.DaysAfterInitiation == days {
				return true
			}
		}
	}

	return false
}

// GetS3BucketVersioning returns the versioning status of an S3 bucket.
// Returns "Enabled", "Suspended", or "" (empty string if versioning was never enabled).
func GetS3BucketVersioning(t *testing.T, bucketName string, region string) string {
	client := getS3Client(t, region)

	input := &s3.GetBucketVersioningInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketVersioning(context.TODO(), input)
	require.NoError(t, err, "Failed to get bucket versioning for %s", bucketName)

	return string(result.Status)
}

// S3BucketHasVersioningEnabled checks if an S3 bucket has versioning enabled.
// Returns true if versioning status is "Enabled".
func S3BucketHasVersioningEnabled(t *testing.T, bucketName string, region string) bool {
	status := GetS3BucketVersioning(t, bucketName, region)
	return status == string(s3types.BucketVersioningStatusEnabled)
}

// S3BucketHasBucketKeyEnabled checks if an S3 bucket has bucket key enabled for SSE-KMS.
// Bucket keys reduce AWS KMS request costs by decreasing the request traffic from S3 to KMS.
// Returns true if bucket key is enabled, false otherwise (including for SSE-S3 buckets).
func S3BucketHasBucketKeyEnabled(t *testing.T, bucketName string, region string) bool {
	client := getS3Client(t, region)

	input := &s3.GetBucketEncryptionInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketEncryption(context.TODO(), input)
	if err != nil {
		// If there's an error getting encryption config, bucket key is not enabled
		return false
	}

	if result.ServerSideEncryptionConfiguration != nil {
		for _, rule := range result.ServerSideEncryptionConfiguration.Rules {
			if rule.BucketKeyEnabled != nil && *rule.BucketKeyEnabled {
				return true
			}
		}
	}

	return false
}

// GetS3BucketTags returns the tags for an S3 bucket as a map.
// Returns an empty map if the bucket has no tags or if fetching tags fails.
func GetS3BucketTags(t *testing.T, bucketName string, region string) map[string]string {
	client := getS3Client(t, region)

	input := &s3.GetBucketTaggingInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketTagging(context.TODO(), input)
	if err != nil {
		// NoSuchTagSet error means the bucket has no tags, which is not an error
		// Return empty map in this case
		return make(map[string]string)
	}

	tags := make(map[string]string)
	for _, tag := range result.TagSet {
		if tag.Key != nil && tag.Value != nil {
			tags[*tag.Key] = *tag.Value
		}
	}

	return tags
}

// S3BucketHasTag checks if an S3 bucket has a specific tag with the expected value.
// Returns true if the tag exists and its value matches expectedValue.
func S3BucketHasTag(t *testing.T, bucketName string, key string, expectedValue string, region string) bool {
	tags := GetS3BucketTags(t, bucketName, region)
	value, exists := tags[key]
	return exists && value == expectedValue
}

// GetS3BucketPolicy returns the bucket policy for an S3 bucket as a JSON string.
// Returns an empty string if the bucket has no policy.
func GetS3BucketPolicy(t *testing.T, bucketName string, region string) string {
	client := getS3Client(t, region)

	input := &s3.GetBucketPolicyInput{
		Bucket: &bucketName,
	}

	result, err := client.GetBucketPolicy(context.TODO(), input)
	if err != nil {
		// NoSuchBucketPolicy error means the bucket has no policy, which is not an error
		// Return empty string in this case
		return ""
	}

	if result.Policy != nil {
		return *result.Policy
	}

	return ""
}

// S3BucketHasPolicy checks if an S3 bucket has a bucket policy attached.
// Returns true if the bucket has a policy, false otherwise.
func S3BucketHasPolicy(t *testing.T, bucketName string, region string) bool {
	policy := GetS3BucketPolicy(t, bucketName, region)
	return policy != ""
}

// S3BucketPolicyContainsStatement checks if an S3 bucket policy contains a statement with the specified Sid.
// Returns true if a statement with the given Sid exists in the policy, false otherwise.
// Note: This performs a simple string search for the Sid pattern in the policy JSON.
// For more complex policy analysis, consider parsing the JSON.
func S3BucketPolicyContainsStatement(t *testing.T, bucketName string, statementSid string, region string) bool {
	policy := GetS3BucketPolicy(t, bucketName, region)
	if policy == "" {
		return false
	}

	// Simple string search for the Sid pattern
	// This looks for patterns like: "Sid": "StatementName" or "Sid":"StatementName"
	// We check for both quoted formats that could appear in JSON
	patterns := []string{
		`"Sid": "` + statementSid + `"`,
		`"Sid":"` + statementSid + `"`,
	}

	for _, pattern := range patterns {
		if containsString(policy, pattern) {
			return true
		}
	}

	return false
}

// containsString checks if a string contains a substring.
// This is a simple helper to avoid importing strings package just for Contains.
func containsString(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// GetLoadBalancerAccessLogsEnabled checks if access logs are enabled for a load balancer.
// Returns true if the access_logs.s3.enabled attribute is "true".
func GetLoadBalancerAccessLogsEnabled(t *testing.T, lbArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancerAttributesInput{
		LoadBalancerArn: &lbArn,
	}

	result, err := client.DescribeLoadBalancerAttributes(context.TODO(), input)
	require.NoError(t, err, "Failed to describe load balancer attributes for %s", lbArn)

	for _, attr := range result.Attributes {
		if attr.Key != nil && *attr.Key == "access_logs.s3.enabled" {
			if attr.Value != nil {
				return *attr.Value == "true"
			}
		}
	}

	return false
}

// GetLoadBalancerAccessLogsBucket returns the S3 bucket name for load balancer access logs.
// Returns an empty string if access logs are not configured.
func GetLoadBalancerAccessLogsBucket(t *testing.T, lbArn string, region string) string {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancerAttributesInput{
		LoadBalancerArn: &lbArn,
	}

	result, err := client.DescribeLoadBalancerAttributes(context.TODO(), input)
	require.NoError(t, err, "Failed to describe load balancer attributes for %s", lbArn)

	for _, attr := range result.Attributes {
		if attr.Key != nil && *attr.Key == "access_logs.s3.bucket" {
			if attr.Value != nil {
				return *attr.Value
			}
		}
	}

	return ""
}

// GetLoadBalancerAccessLogsPrefix returns the S3 prefix for load balancer access logs.
// Returns an empty string if no prefix is configured.
func GetLoadBalancerAccessLogsPrefix(t *testing.T, lbArn string, region string) string {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancerAttributesInput{
		LoadBalancerArn: &lbArn,
	}

	result, err := client.DescribeLoadBalancerAttributes(context.TODO(), input)
	require.NoError(t, err, "Failed to describe load balancer attributes for %s", lbArn)

	for _, attr := range result.Attributes {
		if attr.Key != nil && *attr.Key == "access_logs.s3.prefix" {
			if attr.Value != nil {
				return *attr.Value
			}
		}
	}

	return ""
}

// ################################################################################
// # IAM Helpers
// ################################################################################

// getIAMClient creates an IAM client for the specified region.
// Note: IAM is a global service, but a region is still required for the SDK config.
func getIAMClient(t *testing.T, region string) *iam.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return iam.NewFromConfig(cfg)
}

// IamRoleExists checks if an IAM role with the given name exists.
func IamRoleExists(t *testing.T, roleName string, region string) bool {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	_, err := client.GetRole(context.TODO(), input)
	return err == nil
}

// GetIamRoleArn returns the ARN of an IAM role.
// Returns an empty string if the role doesn't exist.
func GetIamRoleArn(t *testing.T, roleName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	result, err := client.GetRole(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.Role != nil && result.Role.Arn != nil {
		return *result.Role.Arn
	}
	return ""
}

// GetIamRolePath returns the path of an IAM role.
// Returns an empty string if the role doesn't exist.
func GetIamRolePath(t *testing.T, roleName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	result, err := client.GetRole(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.Role != nil && result.Role.Path != nil {
		return *result.Role.Path
	}
	return ""
}

// GetIamRoleDescription returns the description of an IAM role.
// Returns an empty string if the role doesn't exist or has no description.
func GetIamRoleDescription(t *testing.T, roleName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	result, err := client.GetRole(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.Role != nil && result.Role.Description != nil {
		return *result.Role.Description
	}
	return ""
}

// GetIamRoleTrustPolicy returns the trust policy (assume role policy) document for an IAM role.
// The policy is returned as a URL-decoded JSON string.
// Returns an empty string if the role doesn't exist.
func GetIamRoleTrustPolicy(t *testing.T, roleName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	result, err := client.GetRole(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.Role != nil && result.Role.AssumeRolePolicyDocument != nil {
		// The policy document is URL-encoded, so we need to decode it
		decoded, err := url.QueryUnescape(*result.Role.AssumeRolePolicyDocument)
		if err != nil {
			return *result.Role.AssumeRolePolicyDocument
		}
		return decoded
	}
	return ""
}

// IamRoleHasPolicy checks if an IAM role has a specific managed policy attached.
// policyArn should be the full ARN of the managed policy.
func IamRoleHasPolicy(t *testing.T, roleName string, policyArn string, region string) bool {
	client := getIAMClient(t, region)

	input := &iam.ListAttachedRolePoliciesInput{
		RoleName: &roleName,
	}

	result, err := client.ListAttachedRolePolicies(context.TODO(), input)
	if err != nil {
		return false
	}

	for _, policy := range result.AttachedPolicies {
		if policy.PolicyArn != nil && *policy.PolicyArn == policyArn {
			return true
		}
	}

	return false
}

// GetIamRoleAttachedPolicies returns the list of managed policy ARNs attached to an IAM role.
func GetIamRoleAttachedPolicies(t *testing.T, roleName string, region string) []string {
	client := getIAMClient(t, region)

	input := &iam.ListAttachedRolePoliciesInput{
		RoleName: &roleName,
	}

	result, err := client.ListAttachedRolePolicies(context.TODO(), input)
	require.NoError(t, err, "Failed to list attached policies for role %s", roleName)

	var policyArns []string
	for _, policy := range result.AttachedPolicies {
		if policy.PolicyArn != nil {
			policyArns = append(policyArns, *policy.PolicyArn)
		}
	}

	return policyArns
}

// GetIamRoleInlinePolicyNames returns the list of inline policy names attached to an IAM role.
func GetIamRoleInlinePolicyNames(t *testing.T, roleName string, region string) []string {
	client := getIAMClient(t, region)

	input := &iam.ListRolePoliciesInput{
		RoleName: &roleName,
	}

	result, err := client.ListRolePolicies(context.TODO(), input)
	require.NoError(t, err, "Failed to list inline policies for role %s", roleName)

	return result.PolicyNames
}

// GetIamRoleInlinePolicy returns the policy document for an inline policy attached to an IAM role.
// The policy is returned as a URL-decoded JSON string.
// Returns an empty string if the policy doesn't exist.
func GetIamRoleInlinePolicy(t *testing.T, roleName string, policyName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetRolePolicyInput{
		RoleName:   &roleName,
		PolicyName: &policyName,
	}

	result, err := client.GetRolePolicy(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.PolicyDocument != nil {
		// The policy document is URL-encoded, so we need to decode it
		decoded, err := url.QueryUnescape(*result.PolicyDocument)
		if err != nil {
			return *result.PolicyDocument
		}
		return decoded
	}
	return ""
}

// IamInstanceProfileExists checks if an IAM instance profile with the given name exists.
func IamInstanceProfileExists(t *testing.T, instanceProfileName string, region string) bool {
	client := getIAMClient(t, region)

	input := &iam.GetInstanceProfileInput{
		InstanceProfileName: &instanceProfileName,
	}

	_, err := client.GetInstanceProfile(context.TODO(), input)
	return err == nil
}

// GetIamInstanceProfileArn returns the ARN of an IAM instance profile.
// Returns an empty string if the instance profile doesn't exist.
func GetIamInstanceProfileArn(t *testing.T, instanceProfileName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetInstanceProfileInput{
		InstanceProfileName: &instanceProfileName,
	}

	result, err := client.GetInstanceProfile(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.InstanceProfile != nil && result.InstanceProfile.Arn != nil {
		return *result.InstanceProfile.Arn
	}
	return ""
}

// GetIamInstanceProfilePath returns the path of an IAM instance profile.
// Returns an empty string if the instance profile doesn't exist.
func GetIamInstanceProfilePath(t *testing.T, instanceProfileName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetInstanceProfileInput{
		InstanceProfileName: &instanceProfileName,
	}

	result, err := client.GetInstanceProfile(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.InstanceProfile != nil && result.InstanceProfile.Path != nil {
		return *result.InstanceProfile.Path
	}
	return ""
}

// GetIamInstanceProfileRoleName returns the name of the role attached to an IAM instance profile.
// Returns an empty string if the instance profile doesn't exist or has no role attached.
func GetIamInstanceProfileRoleName(t *testing.T, instanceProfileName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetInstanceProfileInput{
		InstanceProfileName: &instanceProfileName,
	}

	result, err := client.GetInstanceProfile(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.InstanceProfile != nil && len(result.InstanceProfile.Roles) > 0 {
		if result.InstanceProfile.Roles[0].RoleName != nil {
			return *result.InstanceProfile.Roles[0].RoleName
		}
	}
	return ""
}

// IamInstanceProfileHasRole checks if an IAM instance profile has a specific role attached.
func IamInstanceProfileHasRole(t *testing.T, instanceProfileName string, roleName string, region string) bool {
	attachedRoleName := GetIamInstanceProfileRoleName(t, instanceProfileName, region)
	return attachedRoleName == roleName
}

// GetIamRoleMaxSessionDuration returns the maximum session duration (in seconds) for an IAM role.
// Returns 0 if the role doesn't exist.
func GetIamRoleMaxSessionDuration(t *testing.T, roleName string, region string) int32 {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	result, err := client.GetRole(context.TODO(), input)
	if err != nil {
		return 0
	}

	if result.Role != nil && result.Role.MaxSessionDuration != nil {
		return *result.Role.MaxSessionDuration
	}
	return 0
}

// GetIamRolePermissionsBoundary returns the ARN of the permissions boundary attached to an IAM role.
// Returns an empty string if the role doesn't exist or has no permissions boundary.
func GetIamRolePermissionsBoundary(t *testing.T, roleName string, region string) string {
	client := getIAMClient(t, region)

	input := &iam.GetRoleInput{
		RoleName: &roleName,
	}

	result, err := client.GetRole(context.TODO(), input)
	if err != nil {
		return ""
	}

	if result.Role != nil && result.Role.PermissionsBoundary != nil && result.Role.PermissionsBoundary.PermissionsBoundaryArn != nil {
		return *result.Role.PermissionsBoundary.PermissionsBoundaryArn
	}
	return ""
}

// GetIamRoleTags returns the tags attached to an IAM role.
func GetIamRoleTags(t *testing.T, roleName string, region string) map[string]string {
	client := getIAMClient(t, region)

	input := &iam.ListRoleTagsInput{
		RoleName: &roleName,
	}

	result, err := client.ListRoleTags(context.TODO(), input)
	if err != nil {
		return nil
	}

	tags := make(map[string]string)
	for _, tag := range result.Tags {
		if tag.Key != nil && tag.Value != nil {
			tags[*tag.Key] = *tag.Value
		}
	}

	return tags
}

// IamRoleHasTag checks if an IAM role has a specific tag with the expected value.
func IamRoleHasTag(t *testing.T, roleName string, tagKey string, tagValue string, region string) bool {
	tags := GetIamRoleTags(t, roleName, region)
	if tags == nil {
		return false
	}
	value, exists := tags[tagKey]
	return exists && value == tagValue
}

// ============================================================================
// EC2 Auto Scaling Group Helpers
// ============================================================================

// getAutoScalingClient creates an Auto Scaling client for the specified region.
func getAutoScalingClient(t *testing.T, region string) *autoscaling.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return autoscaling.NewFromConfig(cfg)
}

// AutoScalingGroupExists checks if an Auto Scaling group with the given name exists in the specified region.
func AutoScalingGroupExists(t *testing.T, asgName string, region string) bool {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.AutoScalingGroups) > 0
}

// GetAutoScalingGroupByArn retrieves an Auto Scaling group by ARN.
func GetAutoScalingGroupByArn(t *testing.T, asgArn string, region string) *autoscaling.DescribeAutoScalingGroupsOutput {
	client := getAutoScalingClient(t, region)

	// AWS API requires name, not ARN, so we need to list and filter
	input := &autoscaling.DescribeAutoScalingGroupsInput{}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling groups")

	for _, asg := range result.AutoScalingGroups {
		if asg.AutoScalingGroupARN != nil && *asg.AutoScalingGroupARN == asgArn {
			return &autoscaling.DescribeAutoScalingGroupsOutput{
				AutoScalingGroups: []autoscalingtypes.AutoScalingGroup{asg},
			}
		}
	}

	return nil
}

// GetAutoScalingGroupMinSize returns the minimum size of an Auto Scaling group.
func GetAutoScalingGroupMinSize(t *testing.T, asgName string, region string) int32 {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	return *result.AutoScalingGroups[0].MinSize
}

// GetAutoScalingGroupMaxSize returns the maximum size of an Auto Scaling group.
func GetAutoScalingGroupMaxSize(t *testing.T, asgName string, region string) int32 {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	return *result.AutoScalingGroups[0].MaxSize
}

// GetAutoScalingGroupDesiredCapacity returns the desired capacity of an Auto Scaling group.
func GetAutoScalingGroupDesiredCapacity(t *testing.T, asgName string, region string) int32 {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	return *result.AutoScalingGroups[0].DesiredCapacity
}

// GetAutoScalingGroupHealthCheckType returns the health check type of an Auto Scaling group.
func GetAutoScalingGroupHealthCheckType(t *testing.T, asgName string, region string) string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	return *result.AutoScalingGroups[0].HealthCheckType
}

// GetAutoScalingGroupAvailabilityZones returns the availability zones of an Auto Scaling group.
func GetAutoScalingGroupAvailabilityZones(t *testing.T, asgName string, region string) []string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	return result.AutoScalingGroups[0].AvailabilityZones
}

// AutoScalingGroupHasLaunchTemplate checks if an Auto Scaling group has a launch template configured.
func AutoScalingGroupHasLaunchTemplate(t *testing.T, asgName string, region string) bool {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	asg := result.AutoScalingGroups[0]

	// Check direct launch template
	if asg.LaunchTemplate != nil && asg.LaunchTemplate.LaunchTemplateId != nil {
		return true
	}

	// Check mixed instances policy
	if asg.MixedInstancesPolicy != nil &&
		asg.MixedInstancesPolicy.LaunchTemplate != nil &&
		asg.MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification != nil &&
		asg.MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification.LaunchTemplateId != nil {
		return true
	}

	return false
}

// AutoScalingGroupHasMixedInstancesPolicy checks if an Auto Scaling group has a mixed instances policy.
func AutoScalingGroupHasMixedInstancesPolicy(t *testing.T, asgName string, region string) bool {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	return result.AutoScalingGroups[0].MixedInstancesPolicy != nil
}

// GetAutoScalingGroupLaunchTemplateId returns the launch template ID used by an Auto Scaling group.
func GetAutoScalingGroupLaunchTemplateId(t *testing.T, asgName string, region string) string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []string{asgName},
	}

	result, err := client.DescribeAutoScalingGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Auto Scaling group %s", asgName)
	require.Len(t, result.AutoScalingGroups, 1, "Expected exactly one Auto Scaling group with name %s", asgName)

	asg := result.AutoScalingGroups[0]

	// Check direct launch template
	if asg.LaunchTemplate != nil && asg.LaunchTemplate.LaunchTemplateId != nil {
		return *asg.LaunchTemplate.LaunchTemplateId
	}

	// Check mixed instances policy
	if asg.MixedInstancesPolicy != nil &&
		asg.MixedInstancesPolicy.LaunchTemplate != nil &&
		asg.MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification != nil &&
		asg.MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification.LaunchTemplateId != nil {
		return *asg.MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification.LaunchTemplateId
	}

	return ""
}

// LaunchTemplateExists checks if a launch template with the given ID exists.
func LaunchTemplateExists(t *testing.T, launchTemplateId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeLaunchTemplatesInput{
		LaunchTemplateIds: []string{launchTemplateId},
	}

	result, err := client.DescribeLaunchTemplates(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.LaunchTemplates) > 0
}

// GetLaunchTemplateLatestVersion returns the latest version number of a launch template.
func GetLaunchTemplateLatestVersion(t *testing.T, launchTemplateId string, region string) int64 {
	client := getEC2Client(t, region)

	input := &ec2.DescribeLaunchTemplatesInput{
		LaunchTemplateIds: []string{launchTemplateId},
	}

	result, err := client.DescribeLaunchTemplates(context.TODO(), input)
	require.NoError(t, err, "Failed to describe launch template %s", launchTemplateId)
	require.Len(t, result.LaunchTemplates, 1, "Expected exactly one launch template with ID %s", launchTemplateId)

	return *result.LaunchTemplates[0].LatestVersionNumber
}

// AutoScalingGroupHasWarmPool checks if an Auto Scaling group has a warm pool configured.
func AutoScalingGroupHasWarmPool(t *testing.T, asgName string, region string) bool {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeWarmPoolInput{
		AutoScalingGroupName: &asgName,
	}

	result, err := client.DescribeWarmPool(context.TODO(), input)
	if err != nil {
		return false
	}

	return result.WarmPoolConfiguration != nil
}

// GetAutoScalingGroupWarmPoolState returns the state of the warm pool for an Auto Scaling group.
func GetAutoScalingGroupWarmPoolState(t *testing.T, asgName string, region string) string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeWarmPoolInput{
		AutoScalingGroupName: &asgName,
	}

	result, err := client.DescribeWarmPool(context.TODO(), input)
	require.NoError(t, err, "Failed to describe warm pool for %s", asgName)
	require.NotNil(t, result.WarmPoolConfiguration, "Warm pool configuration should exist for %s", asgName)

	return string(result.WarmPoolConfiguration.PoolState)
}

// GetAutoScalingPolicies returns the scaling policies for an Auto Scaling group.
func GetAutoScalingPolicies(t *testing.T, asgName string, region string) []string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribePoliciesInput{
		AutoScalingGroupName: &asgName,
	}

	result, err := client.DescribePolicies(context.TODO(), input)
	require.NoError(t, err, "Failed to describe policies for %s", asgName)

	var policyNames []string
	for _, policy := range result.ScalingPolicies {
		if policy.PolicyName != nil {
			policyNames = append(policyNames, *policy.PolicyName)
		}
	}

	return policyNames
}

// GetAutoScalingPolicyCount returns the number of scaling policies for an Auto Scaling group.
func GetAutoScalingPolicyCount(t *testing.T, asgName string, region string) int {
	policies := GetAutoScalingPolicies(t, asgName, region)
	return len(policies)
}

// AutoScalingPolicyExists checks if a scaling policy with the given name exists for an Auto Scaling group.
func AutoScalingPolicyExists(t *testing.T, asgName string, policyName string, region string) bool {
	policies := GetAutoScalingPolicies(t, asgName, region)
	for _, name := range policies {
		if name == policyName {
			return true
		}
	}
	return false
}

// GetAutoScalingLifecycleHooks returns the lifecycle hooks for an Auto Scaling group.
func GetAutoScalingLifecycleHooks(t *testing.T, asgName string, region string) []string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeLifecycleHooksInput{
		AutoScalingGroupName: &asgName,
	}

	result, err := client.DescribeLifecycleHooks(context.TODO(), input)
	require.NoError(t, err, "Failed to describe lifecycle hooks for %s", asgName)

	var hookNames []string
	for _, hook := range result.LifecycleHooks {
		if hook.LifecycleHookName != nil {
			hookNames = append(hookNames, *hook.LifecycleHookName)
		}
	}

	return hookNames
}

// GetAutoScalingLifecycleHookCount returns the number of lifecycle hooks for an Auto Scaling group.
func GetAutoScalingLifecycleHookCount(t *testing.T, asgName string, region string) int {
	hooks := GetAutoScalingLifecycleHooks(t, asgName, region)
	return len(hooks)
}

// AutoScalingLifecycleHookExists checks if a lifecycle hook with the given name exists for an Auto Scaling group.
func AutoScalingLifecycleHookExists(t *testing.T, asgName string, hookName string, region string) bool {
	hooks := GetAutoScalingLifecycleHooks(t, asgName, region)
	for _, name := range hooks {
		if name == hookName {
			return true
		}
	}
	return false
}

// GetAutoScalingScheduledActions returns the scheduled actions for an Auto Scaling group.
func GetAutoScalingScheduledActions(t *testing.T, asgName string, region string) []string {
	client := getAutoScalingClient(t, region)

	input := &autoscaling.DescribeScheduledActionsInput{
		AutoScalingGroupName: &asgName,
	}

	result, err := client.DescribeScheduledActions(context.TODO(), input)
	require.NoError(t, err, "Failed to describe scheduled actions for %s", asgName)

	var actionNames []string
	for _, action := range result.ScheduledUpdateGroupActions {
		if action.ScheduledActionName != nil {
			actionNames = append(actionNames, *action.ScheduledActionName)
		}
	}

	return actionNames
}

// GetAutoScalingScheduledActionCount returns the number of scheduled actions for an Auto Scaling group.
func GetAutoScalingScheduledActionCount(t *testing.T, asgName string, region string) int {
	actions := GetAutoScalingScheduledActions(t, asgName, region)
	return len(actions)
}

// AutoScalingScheduledActionExists checks if a scheduled action with the given name exists for an Auto Scaling group.
func AutoScalingScheduledActionExists(t *testing.T, asgName string, actionName string, region string) bool {
	actions := GetAutoScalingScheduledActions(t, asgName, region)
	for _, name := range actions {
		if name == actionName {
			return true
		}
	}
	return false
}

// ============================================================================
// CloudFront Helpers
// ============================================================================

// getCloudFrontClient creates a CloudFront client.
// CloudFront is a global service, but the SDK still requires a region in config.
func getCloudFrontClient(t *testing.T, region string) *cloudfront.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return cloudfront.NewFromConfig(cfg)
}

// CloudFrontDistributionExists checks if a CloudFront distribution with the given ID exists.
func CloudFrontDistributionExists(t *testing.T, distributionId string, region string) bool {
	client := getCloudFrontClient(t, region)

	input := &cloudfront.GetDistributionInput{
		Id: &distributionId,
	}

	result, err := client.GetDistribution(context.TODO(), input)
	if err != nil {
		return false
	}

	return result.Distribution != nil
}

// GetCloudFrontDistributionStatus returns the status of a CloudFront distribution (e.g., "InProgress", "Deployed").
func GetCloudFrontDistributionStatus(t *testing.T, distributionId string, region string) string {
	client := getCloudFrontClient(t, region)

	input := &cloudfront.GetDistributionInput{
		Id: &distributionId,
	}

	result, err := client.GetDistribution(context.TODO(), input)
	require.NoError(t, err, "Failed to get CloudFront distribution %s", distributionId)
	require.NotNil(t, result.Distribution, "CloudFront distribution %s should exist", distributionId)

	if result.Distribution.Status != nil {
		return *result.Distribution.Status
	}
	return ""
}

// ============================================================================
// Lambda Helpers
// ============================================================================

// getLambdaClient creates a Lambda client for the specified region.
func getLambdaClient(t *testing.T, region string) *lambda.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return lambda.NewFromConfig(cfg)
}

// LambdaFunctionExists checks if a Lambda function with the given name exists.
func LambdaFunctionExists(t *testing.T, functionName string, region string) bool {
	client := getLambdaClient(t, region)

	input := &lambda.GetFunctionInput{
		FunctionName: &functionName,
	}

	result, err := client.GetFunction(context.TODO(), input)
	if err != nil {
		return false
	}

	return result.Configuration != nil
}

// GetLambdaFunctionRuntime returns the configured runtime for a Lambda function.
func GetLambdaFunctionRuntime(t *testing.T, functionName string, region string) string {
	client := getLambdaClient(t, region)

	input := &lambda.GetFunctionInput{
		FunctionName: &functionName,
	}

	result, err := client.GetFunction(context.TODO(), input)
	require.NoError(t, err, "Failed to get Lambda function %s", functionName)
	require.NotNil(t, result.Configuration, "Lambda function %s should have configuration", functionName)

	return string(result.Configuration.Runtime)
}

// GetLambdaFunctionHandler returns the configured handler for a Lambda function.
func GetLambdaFunctionHandler(t *testing.T, functionName string, region string) string {
	client := getLambdaClient(t, region)

	input := &lambda.GetFunctionInput{
		FunctionName: &functionName,
	}

	result, err := client.GetFunction(context.TODO(), input)
	require.NoError(t, err, "Failed to get Lambda function %s", functionName)
	require.NotNil(t, result.Configuration, "Lambda function %s should have configuration", functionName)

	if result.Configuration.Handler != nil {
		return *result.Configuration.Handler
	}
	return ""
}

// GetLambdaFunctionTimeout returns the configured timeout in seconds for a Lambda function.
func GetLambdaFunctionTimeout(t *testing.T, functionName string, region string) int32 {
	client := getLambdaClient(t, region)

	input := &lambda.GetFunctionInput{
		FunctionName: &functionName,
	}

	result, err := client.GetFunction(context.TODO(), input)
	require.NoError(t, err, "Failed to get Lambda function %s", functionName)
	require.NotNil(t, result.Configuration, "Lambda function %s should have configuration", functionName)

	if result.Configuration.Timeout != nil {
		return *result.Configuration.Timeout
	}
	return 0
}

// GetLambdaFunctionRole returns the IAM role ARN used by the Lambda function.
func GetLambdaFunctionRole(t *testing.T, functionName string, region string) string {
	client := getLambdaClient(t, region)

	input := &lambda.GetFunctionInput{
		FunctionName: &functionName,
	}

	result, err := client.GetFunction(context.TODO(), input)
	require.NoError(t, err, "Failed to get Lambda function %s", functionName)
	require.NotNil(t, result.Configuration, "Lambda function %s should have configuration", functionName)

	if result.Configuration.Role != nil {
		return *result.Configuration.Role
	}
	return ""
}

// ============================================================================
// Aurora / RDS Cluster Helpers
// ============================================================================

// getRDSClient creates an RDS client for the specified region.
func getRDSClient(t *testing.T, region string) *rds.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return rds.NewFromConfig(cfg)
}

// RDSInstanceExists checks if an RDS DB instance with the given identifier exists.
func RDSInstanceExists(t *testing.T, instanceIdentifier string, region string) bool {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.DBInstances) > 0
}

// GetRDSInstanceStatus returns the status of an RDS DB instance.
func GetRDSInstanceStatus(t *testing.T, instanceIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	require.NoError(t, err, "Failed to describe RDS instance %s", instanceIdentifier)
	require.Len(t, result.DBInstances, 1, "Expected exactly one RDS instance with identifier %s", instanceIdentifier)

	if result.DBInstances[0].DBInstanceStatus != nil {
		return *result.DBInstances[0].DBInstanceStatus
	}
	return ""
}

// GetRDSInstanceEngine returns the engine for an RDS DB instance (e.g., "postgres", "mysql").
func GetRDSInstanceEngine(t *testing.T, instanceIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	require.NoError(t, err, "Failed to describe RDS instance %s", instanceIdentifier)
	require.Len(t, result.DBInstances, 1, "Expected exactly one RDS instance with identifier %s", instanceIdentifier)

	if result.DBInstances[0].Engine != nil {
		return *result.DBInstances[0].Engine
	}
	return ""
}

// GetRDSInstanceClass returns the instance class for an RDS DB instance.
func GetRDSInstanceClass(t *testing.T, instanceIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	require.NoError(t, err, "Failed to describe RDS instance %s", instanceIdentifier)
	require.Len(t, result.DBInstances, 1, "Expected exactly one RDS instance with identifier %s", instanceIdentifier)

	if result.DBInstances[0].DBInstanceClass != nil {
		return *result.DBInstances[0].DBInstanceClass
	}
	return ""
}

// IsRDSInstanceStorageEncrypted returns true if storage encryption is enabled for an RDS DB instance.
func IsRDSInstanceStorageEncrypted(t *testing.T, instanceIdentifier string, region string) bool {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	require.NoError(t, err, "Failed to describe RDS instance %s", instanceIdentifier)
	require.Len(t, result.DBInstances, 1, "Expected exactly one RDS instance with identifier %s", instanceIdentifier)

	if result.DBInstances[0].StorageEncrypted != nil {
		return *result.DBInstances[0].StorageEncrypted
	}
	return false
}

// AuroraClusterExists checks if an Aurora cluster with the given identifier exists.
func AuroraClusterExists(t *testing.T, clusterIdentifier string, region string) bool {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.DBClusters) > 0
}

// GetAuroraClusterStatus returns the status of an Aurora cluster.
func GetAuroraClusterStatus(t *testing.T, clusterIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	if result.DBClusters[0].Status != nil {
		return *result.DBClusters[0].Status
	}
	return ""
}

// GetAuroraClusterEngine returns the engine of an Aurora cluster (e.g., "aurora-mysql", "aurora-postgresql").
func GetAuroraClusterEngine(t *testing.T, clusterIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	if result.DBClusters[0].Engine != nil {
		return *result.DBClusters[0].Engine
	}
	return ""
}

// GetAuroraClusterMemberCount returns the number of DB instances in an Aurora cluster.
func GetAuroraClusterMemberCount(t *testing.T, clusterIdentifier string, region string) int {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	return len(result.DBClusters[0].DBClusterMembers)
}

// GetAuroraClusterWriterCount returns the number of writer instances in an Aurora cluster.
func GetAuroraClusterWriterCount(t *testing.T, clusterIdentifier string, region string) int {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	writerCount := 0
	for _, member := range result.DBClusters[0].DBClusterMembers {
		if member.IsClusterWriter != nil && *member.IsClusterWriter {
			writerCount++
		}
	}
	return writerCount
}

// GetAuroraClusterReaderCount returns the number of reader instances in an Aurora cluster.
func GetAuroraClusterReaderCount(t *testing.T, clusterIdentifier string, region string) int {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	readerCount := 0
	for _, member := range result.DBClusters[0].DBClusterMembers {
		if member.IsClusterWriter == nil || !*member.IsClusterWriter {
			readerCount++
		}
	}
	return readerCount
}

// GetAuroraClusterPort returns the port of an Aurora cluster.
func GetAuroraClusterPort(t *testing.T, clusterIdentifier string, region string) int32 {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	if result.DBClusters[0].Port != nil {
		return *result.DBClusters[0].Port
	}
	return 0
}

// GetAuroraClusterBacktrackWindow returns the backtrack window (in seconds) for an Aurora cluster.
func GetAuroraClusterBacktrackWindow(t *testing.T, clusterIdentifier string, region string) int64 {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	if result.DBClusters[0].BacktrackWindow != nil {
		return *result.DBClusters[0].BacktrackWindow
	}
	return 0
}

// AuroraInstanceExists checks if an Aurora DB instance with the given identifier exists.
func AuroraInstanceExists(t *testing.T, instanceIdentifier string, region string) bool {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.DBInstances) > 0
}

// GetAuroraInstanceStatus returns the status of an Aurora DB instance.
func GetAuroraInstanceStatus(t *testing.T, instanceIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora instance %s", instanceIdentifier)
	require.Len(t, result.DBInstances, 1, "Expected exactly one instance with identifier %s", instanceIdentifier)

	if result.DBInstances[0].DBInstanceStatus != nil {
		return *result.DBInstances[0].DBInstanceStatus
	}
	return ""
}

// GetAuroraInstanceClass returns the instance class of an Aurora DB instance.
func GetAuroraInstanceClass(t *testing.T, instanceIdentifier string, region string) string {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceIdentifier,
	}

	result, err := client.DescribeDBInstances(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora instance %s", instanceIdentifier)
	require.Len(t, result.DBInstances, 1, "Expected exactly one instance with identifier %s", instanceIdentifier)

	if result.DBInstances[0].DBInstanceClass != nil {
		return *result.DBInstances[0].DBInstanceClass
	}
	return ""
}

// AllAuroraClusterMembersAvailable checks if all DB instances in an Aurora cluster are available.
func AllAuroraClusterMembersAvailable(t *testing.T, clusterIdentifier string, region string) bool {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	for _, member := range result.DBClusters[0].DBClusterMembers {
		if member.DBInstanceIdentifier == nil {
			return false
		}
		status := GetAuroraInstanceStatus(t, *member.DBInstanceIdentifier, region)
		if status != "available" {
			return false
		}
	}
	return true
}

// AuroraClusterEndpointExists checks if a custom endpoint exists for an Aurora cluster.
func AuroraClusterEndpointExists(t *testing.T, endpointIdentifier string, region string) bool {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClusterEndpointsInput{
		DBClusterEndpointIdentifier: &endpointIdentifier,
	}

	result, err := client.DescribeDBClusterEndpoints(context.TODO(), input)
	if err != nil {
		return false
	}

	// Filter to only custom endpoints (exclude WRITER and READER built-in endpoints)
	for _, ep := range result.DBClusterEndpoints {
		if ep.CustomEndpointType != nil {
			return true
		}
	}
	return len(result.DBClusterEndpoints) > 0
}

// GetAuroraClusterCustomEndpointCount returns the number of custom endpoints for a cluster.
func GetAuroraClusterCustomEndpointCount(t *testing.T, clusterIdentifier string, region string) int {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClusterEndpointsInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusterEndpoints(context.TODO(), input)
	require.NoError(t, err, "Failed to describe cluster endpoints for %s", clusterIdentifier)

	customCount := 0
	for _, ep := range result.DBClusterEndpoints {
		if ep.CustomEndpointType != nil && *ep.CustomEndpointType != "" {
			customCount++
		}
	}
	return customCount
}

// RDSAppAutoScalingTargetExists checks if an Application Auto Scaling target exists for an RDS resource.
// resourceId should be in the format "cluster:{cluster-identifier}" for Aurora.
func RDSAppAutoScalingTargetExists(t *testing.T, resourceId string, region string) bool {
	client := getApplicationAutoScalingClient(t, region)

	input := &applicationautoscaling.DescribeScalableTargetsInput{
		ServiceNamespace: applicationautoscalingtypes.ServiceNamespaceRds,
		ResourceIds:      []string{resourceId},
	}

	result, err := client.DescribeScalableTargets(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.ScalableTargets) > 0
}

// GetRDSAppAutoScalingPolicyCount returns the number of scaling policies for an RDS auto-scaling target.
// resourceId should be in the format "cluster:{cluster-identifier}" for Aurora.
func GetRDSAppAutoScalingPolicyCount(t *testing.T, resourceId string, region string) int {
	client := getApplicationAutoScalingClient(t, region)

	input := &applicationautoscaling.DescribeScalingPoliciesInput{
		ServiceNamespace: applicationautoscalingtypes.ServiceNamespaceRds,
		ResourceId:       &resourceId,
	}

	result, err := client.DescribeScalingPolicies(context.TODO(), input)
	require.NoError(t, err, "Failed to describe RDS scaling policies for %s", resourceId)

	return len(result.ScalingPolicies)
}

// GetAuroraClusterServerlessV2ScalingConfig returns the serverless v2 scaling configuration for a cluster.
// Returns (minCapacity, maxCapacity, hasConfig).
func GetAuroraClusterServerlessV2ScalingConfig(t *testing.T, clusterIdentifier string, region string) (float64, float64, bool) {
	client := getRDSClient(t, region)

	input := &rds.DescribeDBClustersInput{
		DBClusterIdentifier: &clusterIdentifier,
	}

	result, err := client.DescribeDBClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe Aurora cluster %s", clusterIdentifier)
	require.Len(t, result.DBClusters, 1, "Expected exactly one cluster with identifier %s", clusterIdentifier)

	if result.DBClusters[0].ServerlessV2ScalingConfiguration != nil {
		cfg := result.DBClusters[0].ServerlessV2ScalingConfiguration
		minCap := 0.0
		maxCap := 0.0
		if cfg.MinCapacity != nil {
			minCap = *cfg.MinCapacity
		}
		if cfg.MaxCapacity != nil {
			maxCap = *cfg.MaxCapacity
		}
		return minCap, maxCap, true
	}
	return 0, 0, false
}

// describeTargetGroup returns the target group with the given ARN, failing the test if it is missing.
func describeTargetGroup(t *testing.T, targetGroupArn string, region string) elbv2types.TargetGroup {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	return result.TargetGroups[0]
}

// TargetGroupExistsByName checks if a target group with the given name exists.
// Unlike TargetGroupExists this does not need an ARN, so it can assert that a
// target group was never created.
func TargetGroupExistsByName(t *testing.T, targetGroupName string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		Names: []string{targetGroupName},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.TargetGroups) > 0
}

// GetTargetGroupName returns the name of a target group.
func GetTargetGroupName(t *testing.T, targetGroupArn string, region string) string {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.TargetGroupName != nil {
		return *targetGroup.TargetGroupName
	}
	return ""
}

// GetTargetGroupVpcId returns the ID of the VPC a target group was created in.
func GetTargetGroupVpcId(t *testing.T, targetGroupArn string, region string) string {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.VpcId != nil {
		return *targetGroup.VpcId
	}
	return ""
}

// GetTargetGroupHealthCheckEnabled returns whether health checks are enabled on a target group.
func GetTargetGroupHealthCheckEnabled(t *testing.T, targetGroupArn string, region string) bool {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.HealthCheckEnabled != nil {
		return *targetGroup.HealthCheckEnabled
	}
	return false
}

// GetTargetGroupHealthCheckPath returns the health check path of a target group.
func GetTargetGroupHealthCheckPath(t *testing.T, targetGroupArn string, region string) string {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.HealthCheckPath != nil {
		return *targetGroup.HealthCheckPath
	}
	return ""
}

// GetTargetGroupHealthCheckPort returns the health check port of a target group.
func GetTargetGroupHealthCheckPort(t *testing.T, targetGroupArn string, region string) string {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.HealthCheckPort != nil {
		return *targetGroup.HealthCheckPort
	}
	return ""
}

// GetTargetGroupHealthCheckProtocol returns the protocol used for a target group's health checks.
func GetTargetGroupHealthCheckProtocol(t *testing.T, targetGroupArn string, region string) elbv2types.ProtocolEnum {
	return describeTargetGroup(t, targetGroupArn, region).HealthCheckProtocol
}

// GetTargetGroupHealthCheckMatcher returns the HTTP status code matcher of a target group's health check.
func GetTargetGroupHealthCheckMatcher(t *testing.T, targetGroupArn string, region string) string {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.Matcher != nil && targetGroup.Matcher.HttpCode != nil {
		return *targetGroup.Matcher.HttpCode
	}
	return ""
}

// GetTargetGroupHealthCheckInterval returns the health check interval, in seconds.
func GetTargetGroupHealthCheckInterval(t *testing.T, targetGroupArn string, region string) int32 {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.HealthCheckIntervalSeconds != nil {
		return *targetGroup.HealthCheckIntervalSeconds
	}
	return 0
}

// GetTargetGroupHealthCheckTimeout returns the health check timeout, in seconds.
func GetTargetGroupHealthCheckTimeout(t *testing.T, targetGroupArn string, region string) int32 {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.HealthCheckTimeoutSeconds != nil {
		return *targetGroup.HealthCheckTimeoutSeconds
	}
	return 0
}

// GetTargetGroupHealthyThreshold returns the number of consecutive successful health checks
// required before a target is considered healthy.
func GetTargetGroupHealthyThreshold(t *testing.T, targetGroupArn string, region string) int32 {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.HealthyThresholdCount != nil {
		return *targetGroup.HealthyThresholdCount
	}
	return 0
}

// GetTargetGroupUnhealthyThreshold returns the number of consecutive failed health checks
// required before a target is considered unhealthy.
func GetTargetGroupUnhealthyThreshold(t *testing.T, targetGroupArn string, region string) int32 {
	targetGroup := describeTargetGroup(t, targetGroupArn, region)

	if targetGroup.UnhealthyThresholdCount != nil {
		return *targetGroup.UnhealthyThresholdCount
	}
	return 0
}

// GetTargetGroupAttributes returns all target group attributes as a map, e.g.
// "deregistration_delay.timeout_seconds", "slow_start.duration_seconds", "stickiness.enabled".
func GetTargetGroupAttributes(t *testing.T, targetGroupArn string, region string) map[string]string {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupAttributesInput{
		TargetGroupArn: &targetGroupArn,
	}

	result, err := client.DescribeTargetGroupAttributes(context.TODO(), input)
	require.NoError(t, err, "Failed to describe attributes for target group %s", targetGroupArn)

	attributes := make(map[string]string)
	for _, attribute := range result.Attributes {
		if attribute.Key != nil && attribute.Value != nil {
			attributes[*attribute.Key] = *attribute.Value
		}
	}

	return attributes
}

// GetTargetGroupAttribute returns a single target group attribute value, or "" if it is not set.
func GetTargetGroupAttribute(t *testing.T, targetGroupArn string, attributeKey string, region string) string {
	return GetTargetGroupAttributes(t, targetGroupArn, region)[attributeKey]
}

// describeListenerRule returns the listener rule with the given ARN, failing the test if it is missing.
func describeListenerRule(t *testing.T, ruleArn string, region string) elbv2types.Rule {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeRulesInput{
		RuleArns: []string{ruleArn},
	}

	result, err := client.DescribeRules(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener rule %s", ruleArn)
	require.Len(t, result.Rules, 1, "Expected exactly one listener rule with ARN %s", ruleArn)

	return result.Rules[0]
}

// ListenerRuleExists checks if a listener rule with the given ARN exists.
func ListenerRuleExists(t *testing.T, ruleArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeRulesInput{
		RuleArns: []string{ruleArn},
	}

	result, err := client.DescribeRules(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.Rules) > 0
}

// GetListenerRulePriority returns the priority of a listener rule. AWS reports
// priorities as strings ("default" for the listener's default rule).
func GetListenerRulePriority(t *testing.T, ruleArn string, region string) string {
	rule := describeListenerRule(t, ruleArn, region)

	if rule.Priority != nil {
		return *rule.Priority
	}
	return ""
}

// GetListenerRuleTargetGroupArn returns the ARN of the target group a listener rule forwards to.
func GetListenerRuleTargetGroupArn(t *testing.T, ruleArn string, region string) string {
	rule := describeListenerRule(t, ruleArn, region)

	for _, action := range rule.Actions {
		if action.TargetGroupArn != nil {
			return *action.TargetGroupArn
		}
		if action.ForwardConfig != nil {
			for _, targetGroup := range action.ForwardConfig.TargetGroups {
				if targetGroup.TargetGroupArn != nil {
					return *targetGroup.TargetGroupArn
				}
			}
		}
	}

	return ""
}

// GetListenerRulePathPatterns returns the path patterns a listener rule matches on.
func GetListenerRulePathPatterns(t *testing.T, ruleArn string, region string) []string {
	rule := describeListenerRule(t, ruleArn, region)

	var patterns []string
	for _, condition := range rule.Conditions {
		if condition.Field == nil || *condition.Field != "path-pattern" {
			continue
		}
		if condition.PathPatternConfig != nil {
			patterns = append(patterns, condition.PathPatternConfig.Values...)
			continue
		}
		patterns = append(patterns, condition.Values...)
	}

	return patterns
}

// GetListenerRuleArnsForListener returns the ARNs of every non-default rule on a listener.
func GetListenerRuleArnsForListener(t *testing.T, listenerArn string, region string) []string {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeRulesInput{
		ListenerArn: &listenerArn,
	}

	result, err := client.DescribeRules(context.TODO(), input)
	require.NoError(t, err, "Failed to describe rules for listener %s", listenerArn)

	var ruleArns []string
	for _, rule := range result.Rules {
		if rule.IsDefault != nil && *rule.IsDefault {
			continue
		}
		if rule.RuleArn != nil {
			ruleArns = append(ruleArns, *rule.RuleArn)
		}
	}

	return ruleArns
}

// getECRClient creates an ECR client for the specified region.
func getECRClient(t *testing.T, region string) *ecr.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return ecr.NewFromConfig(cfg)
}

// describeEcrRepository returns the ECR repository with the given name, failing the test if it is missing.
func describeEcrRepository(t *testing.T, repositoryName string, region string) ecrtypes.Repository {
	client := getECRClient(t, region)

	input := &ecr.DescribeRepositoriesInput{
		RepositoryNames: []string{repositoryName},
	}

	result, err := client.DescribeRepositories(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECR repository %s", repositoryName)
	require.Len(t, result.Repositories, 1, "Expected exactly one ECR repository named %s", repositoryName)

	return result.Repositories[0]
}

// EcrRepositoryExists checks if an ECR repository with the given name exists.
func EcrRepositoryExists(t *testing.T, repositoryName string, region string) bool {
	client := getECRClient(t, region)

	input := &ecr.DescribeRepositoriesInput{
		RepositoryNames: []string{repositoryName},
	}

	result, err := client.DescribeRepositories(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.Repositories) > 0
}

// GetEcrRepositoryArn returns the ARN of an ECR repository.
func GetEcrRepositoryArn(t *testing.T, repositoryName string, region string) string {
	repository := describeEcrRepository(t, repositoryName, region)

	if repository.RepositoryArn != nil {
		return *repository.RepositoryArn
	}
	return ""
}

// GetEcrRepositoryUri returns the URI of an ECR repository.
func GetEcrRepositoryUri(t *testing.T, repositoryName string, region string) string {
	repository := describeEcrRepository(t, repositoryName, region)

	if repository.RepositoryUri != nil {
		return *repository.RepositoryUri
	}
	return ""
}

// GetEcrRepositoryImageTagMutability returns the tag mutability setting (MUTABLE or IMMUTABLE)
// of an ECR repository.
func GetEcrRepositoryImageTagMutability(t *testing.T, repositoryName string, region string) ecrtypes.ImageTagMutability {
	return describeEcrRepository(t, repositoryName, region).ImageTagMutability
}

// GetEcrRepositoryScanOnPushEnabled returns whether an ECR repository scans images on push.
func GetEcrRepositoryScanOnPushEnabled(t *testing.T, repositoryName string, region string) bool {
	repository := describeEcrRepository(t, repositoryName, region)

	if repository.ImageScanningConfiguration != nil {
		return repository.ImageScanningConfiguration.ScanOnPush
	}
	return false
}

// EcrRepositoryHasLifecyclePolicy checks if an ECR repository has a lifecycle policy applied.
func EcrRepositoryHasLifecyclePolicy(t *testing.T, repositoryName string, region string) bool {
	client := getECRClient(t, region)

	input := &ecr.GetLifecyclePolicyInput{
		RepositoryName: &repositoryName,
	}

	result, err := client.GetLifecyclePolicy(context.TODO(), input)
	if err != nil {
		return false
	}

	return result.LifecyclePolicyText != nil && *result.LifecyclePolicyText != ""
}
