# Terratest Integration Tests

This directory contains [Terratest](https://terratest.gruntwork.io/) integration tests for the Terraform modules in this repository. These tests provision real AWS infrastructure, validate it works correctly, and then destroy it.

## Directory Structure

```
test/
├── README.md              # This file
├── go.mod                 # Go module definition
├── go.sum                 # Go dependency checksums
├── .env.test.example      # Example environment file (copy to .env.test)
├── helpers/               # Shared helper functions
│   ├── aws.go             # AWS SDK helper functions
│   ├── env.go             # Environment variable loading (.env.test support)
│   ├── random.go          # Random name generation helpers
│   └── tags.go            # Tag validation helpers
├── fixtures/              # Terraform configurations for testing
│   ├── alb/               # ALB module fixtures
│   │   ├── basic/
│   │   ├── with_https/
│   │   ├── with_waf/
│   │   └── with_access_logs/
│   ├── ecs_cluster/       # ECS cluster module fixtures
│   │   ├── fargate/
│   │   ├── fargate_spot/
│   │   └── with_alb/
│   ├── ecs_service/       # ECS service module fixtures
│   │   ├── basic/
│   │   ├── with_alb/
│   │   └── with_autoscaling/
│   ├── eks_service/       # EKS service module fixtures
│   │   ├── with_alb/
│   │   ├── worker/
│   │   ├── with_alb_and_ecr/
│   │   └── with_ecr_name_override/
│   ├── elasticache/       # ElastiCache module fixtures
│   │   ├── redis/
│   │   ├── memcached/
│   │   └── redis_replication/
│   ├── nlb/               # NLB module fixtures
│   │   ├── basic/
│   │   └── with_cross_zone/
│   ├── s3/                # S3 module fixtures
│   │   ├── basic/
│   │   ├── with_kms/
│   │   ├── with_versioning/
│   │   ├── with_lifecycle/
│   │   ├── with_alb_logs_policy/
│   │   ├── with_vpc_flow_logs_policy/
│   │   ├── with_nlb_logs_policy/
│   │   ├── with_custom_policy/
│   │   └── full/
│   ├── security_groups/   # Security groups module fixtures
│   │   ├── basic/
│   │   └── with_egress/
│   └── vpc/               # VPC module fixtures
│       ├── basic/
│       ├── with_nat/
│       ├── full/
│       └── with_flow_logs_s3/
├── alb_test.go            # ALB integration tests
├── ecs_cluster_test.go    # ECS cluster integration tests
├── ecs_service_test.go    # ECS service integration tests
├── eks_service_test.go    # EKS service integration tests
├── elasticache_test.go    # ElastiCache integration tests
├── nlb_test.go            # NLB integration tests
├── s3_test.go             # S3 integration tests
├── security_groups_test.go # Security groups integration tests
└── vpc_test.go            # VPC integration tests
```

## Prerequisites

- **Go 1.23+**: Required for running tests
- **OpenTofu/Terraform 1.0+**: Required for provisioning infrastructure
- **AWS CLI configured**: With credentials that have permissions to create/destroy resources

## Environment Variables

The following environment variables must be set:

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_ACCESS_KEY_ID` | Yes | AWS access key for authentication |
| `AWS_SECRET_ACCESS_KEY` | Yes | AWS secret key for authentication |
| `AWS_REGION` | No | AWS region (defaults to `us-east-1`) |

### Using `.env.test` File (Recommended)

Instead of setting environment variables manually, you can use a `.env.test` file that is automatically loaded when tests run:

```bash
# Copy the example file
cp .env.test.example .env.test

# Edit with your credentials
vim .env.test
```

The `.env.test` file is git-ignored to prevent accidental credential commits.

**Example `.env.test`:**
```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
```

### Using Shell Environment Variables

Alternatively, export variables directly:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

## Running Tests

### Run All Tests

```bash
cd test
go test -v -timeout 60m ./...
```

### Run a Specific Test

```bash
cd test
go test -v -timeout 30m -run TestVpcBasic ./...
```

### Run Tests for a Specific Module

```bash
# VPC tests
go test -v -timeout 60m -run TestVpc ./...

# ALB tests
go test -v -timeout 60m -run TestAlb ./...

# ECS tests
go test -v -timeout 60m -run TestEcs ./...

# ElastiCache tests
go test -v -timeout 60m -run TestElastiCache ./...

# S3 tests
go test -v -timeout 60m -run TestS3 ./...
```

### Run Tests with Parallel Execution

Tests use `t.Parallel()` and can run concurrently:

```bash
go test -v -timeout 60m -parallel 4 ./...
```

## Test Fixtures

Fixtures are minimal Terraform configurations that instantiate modules for testing. Each fixture:

1. Creates any prerequisite resources (e.g., VPC for ALB tests)
2. Instantiates the module being tested
3. Outputs values needed for assertions
4. Uses standard terratest tags (`Environment=terratest`, `ManagedBy=terratest`)

### Fixture Conventions

- Each fixture is a self-contained Terraform configuration in `fixtures/<module>/<variant>/`
- Fixtures accept at minimum `name` and `region` variables
- Fixtures include standard terratest tags for resource identification
- Outputs should provide all values needed for test assertions

### Creating a New Fixture

1. Create a new directory under `fixtures/<module>/<variant>/`
2. Create `main.tf` with:
   - Required providers block
   - Provider configuration
   - Variables for `name`, `region`, and `tags`
   - Module instantiation with test configuration
   - Outputs for test assertions

Example structure:
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

module "example" {
  source = "../../../../path/to/module"

  name = var.name
  # ... module configuration

  tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
}

output "example_id" {
  value = module.example.id
}
```

## Helper Functions

### random.go

- `UniqueResourceName(prefix string) string`: Generates `terratest-{prefix}-{uniqueId}`
- `UniqueId() string`: Returns a lowercase unique identifier

### aws.go

AWS SDK helper functions for validating resources:

**VPC helpers:**
- `GetAwsRegion() string`: Returns AWS region from env or default
- `VpcExists(t, vpcId, region) bool`: Check if VPC exists
- `SubnetsExist(t, subnetIds, region) bool`: Check if subnets exist
- `GetVpcCidr(t, vpcId, region) string`: Get VPC CIDR block
- `GetVpcIpv6CidrBlock(t, vpcId, region) string`: Get VPC IPv6 CIDR
- `VpcHasIpv6CidrBlock(t, vpcId, region) bool`: Check IPv6 support

**NAT Gateway helpers:**
- `NatGatewayExists(t, natGatewayId, region) bool`: Check if NAT GW exists
- `GetNatGatewayState(t, natGatewayId, region) NatGatewayState`: Get state
- `RouteTableHasNatGatewayRoute(t, routeTableId, region) bool`: Check routes

**Load Balancer helpers:**
- `LoadBalancerExists(t, albArn, region) bool`: Check if LB exists
- `GetLoadBalancerState(t, albArn, region) LoadBalancerStateEnum`: Get state
- `GetLoadBalancerCrossZoneEnabled(t, lbArn, region) bool`: Check cross-zone
- `GetLoadBalancerAccessLogsEnabled(t, lbArn, region) bool`: Check access logs

**Security Group helpers:**
- `SecurityGroupExists(t, sgId, region) bool`: Check if SG exists
- `SecurityGroupHasIngressRule(t, sgId, port, region) bool`: Check ingress
- `SecurityGroupHasEgressRule(t, sgId, port, region) bool`: Check egress

**ECS helpers:**
- `EcsClusterExists(t, clusterArn, region) bool`: Check if cluster exists
- `GetEcsClusterStatus(t, clusterArn, region) string`: Get cluster status
- `EcsClusterHasCapacityProvider(t, clusterArn, provider, region) bool`: Check provider
- `EcsServiceExists(t, clusterArn, serviceName, region) bool`: Check service
- `GetEcsServiceRunningCount(t, clusterArn, serviceName, region) int32`: Get running tasks

**Target Group / Listener Rule helpers:**
- `TargetGroupExists(t, tgArn, region) bool`: Check target group by ARN
- `TargetGroupExistsByName(t, tgName, region) bool`: Check target group by name (asserts absence)
- `GetTargetGroupName/VpcId/Port/Protocol/TargetType(t, tgArn, region)`: Core attributes
- `GetTargetGroupHealthCheck*(t, tgArn, region)`: Health check path, port, protocol, matcher, interval, timeout, thresholds
- `GetTargetGroupAttributes(t, tgArn, region) map[string]string`: Deregistration delay, slow start, stickiness
- `ListenerRuleExists(t, ruleArn, region) bool`: Check if a listener rule exists
- `GetListenerRulePriority/TargetGroupArn/PathPatterns(t, ruleArn, region)`: Rule wiring
- `GetListenerRuleArnsForListener(t, listenerArn, region) []string`: Non-default rules on a listener

**ECR helpers:**
- `EcrRepositoryExists(t, repoName, region) bool`: Check if repository exists
- `GetEcrRepositoryArn(t, repoName, region) string`: Get repository ARN
- `GetEcrRepositoryUri(t, repoName, region) string`: Get repository URI
- `GetEcrRepositoryImageTagMutability(t, repoName, region) ImageTagMutability`: MUTABLE or IMMUTABLE
- `GetEcrRepositoryScanOnPushEnabled(t, repoName, region) bool`: Check scan-on-push
- `EcrRepositoryHasLifecyclePolicy(t, repoName, region) bool`: Check lifecycle policy applied

**ElastiCache helpers:**
- `ElastiCacheReplicationGroupExists(t, rgId, region) bool`: Check Redis exists
- `GetElastiCacheReplicationGroupStatus(t, rgId, region) string`: Get status
- `ElastiCacheClusterExists(t, clusterId, region) bool`: Check Memcached exists

**S3 helpers:**
- `S3BucketExists(t, bucketName, region) bool`: Check if bucket exists
- `GetS3BucketEncryption(t, bucketName, region) (algorithm, kmsKeyId)`: Get encryption config
- `S3BucketHasSSEEncryption(t, bucketName, region) bool`: Check encryption enabled
- `GetS3BucketPublicAccessBlock(t, bucketName, region) *PublicAccessBlockConfiguration`: Get full config
- `S3BucketHasPublicAccessBlocked(t, bucketName, region) bool`: Check all public access blocked
- `GetS3BucketLifecycleRules(t, bucketName, region) []LifecycleRule`: Get all lifecycle rules
- `S3BucketHasExpirationRule(t, bucketName, days, region) bool`: Check expiration rule
- `S3BucketHasTransitionRule(t, bucketName, ruleId, storageClass, days, region) bool`: Check transition
- `S3BucketHasNoncurrentVersionExpiration(t, bucketName, ruleId, days, region) bool`: Check noncurrent expiration
- `S3BucketHasAbortMultipartUploadRule(t, bucketName, ruleId, days, region) bool`: Check multipart abort
- `GetS3BucketVersioning(t, bucketName, region) string`: Get versioning status
- `S3BucketHasVersioningEnabled(t, bucketName, region) bool`: Check versioning enabled
- `S3BucketHasBucketKeyEnabled(t, bucketName, region) bool`: Check bucket key enabled (KMS)
- `GetS3BucketTags(t, bucketName, region) map[string]string`: Get all bucket tags
- `S3BucketHasTag(t, bucketName, key, expectedValue, region) bool`: Check specific tag
- `GetS3BucketPolicy(t, bucketName, region) string`: Get bucket policy JSON
- `S3BucketHasPolicy(t, bucketName, region) bool`: Check if policy exists
- `S3BucketPolicyContainsStatement(t, bucketName, statementSid, region) bool`: Check for statement

**WAF helpers:**
- `WafWebAclExists(t, webAclArn, region) bool`: Check if WebACL exists
- `WafWebAclHasManagedRuleGroup(t, webAclArn, ruleName, region) bool`: Check rules

### tags.go

- `HasTag(tags, key, value) bool`: Check for specific tag
- `ValidateRequiredTags(t, tags, required) bool`: Validate required tags exist
- `ValidateTerratestTags(t, tags)`: Validate standard terratest tags

## Writing New Tests

### Test Structure

```go
func TestModuleFeature(t *testing.T) {
    t.Parallel()

    // Get AWS region
    awsRegion := helpers.GetAwsRegion()

    // Generate unique name
    uniqueName := helpers.UniqueResourceName("feature")

    // Configure Terraform
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "./fixtures/module/feature",
        Vars: map[string]interface{}{
            "name":   uniqueName,
            "region": awsRegion,
        },
    })

    // Always destroy resources
    defer terraform.Destroy(t, terraformOptions)

    // Apply configuration
    terraform.InitAndApply(t, terraformOptions)

    // Get outputs
    resourceId := terraform.Output(t, terraformOptions, "resource_id")

    // Assert Terraform outputs
    require.NotEmpty(t, resourceId, "resource_id should not be empty")

    // Validate with AWS SDK
    exists := helpers.ResourceExists(t, resourceId, awsRegion)
    assert.True(t, exists, "Resource should exist in AWS")
}
```

### Best Practices

1. **Always use `t.Parallel()`**: Allows tests to run concurrently
2. **Always use `defer terraform.Destroy()`**: Ensures cleanup even on failures
3. **Use unique names**: Prevents conflicts between parallel tests
4. **Validate with AWS SDK**: Don't just trust Terraform outputs
5. **Use meaningful assertions**: Provide context in failure messages
6. **Keep fixtures minimal**: Only configure what's needed for the test

## CI/CD Integration

Tests run automatically via GitHub Actions:

- **Native tests (`tofu test`)**: Run on all PRs and pushes to main
- **Integration tests (Terratest)**: Run on pushes to main or PRs with `run-terratest` label

See `.github/workflows/terratest.yml` for the workflow configuration.

### Running Integration Tests on PRs

Add the `run-terratest` label to a PR to trigger integration tests before merging.

## Cost Considerations

These tests provision real AWS resources that incur costs:

- **VPC**: Minimal cost (NAT Gateways cost ~$0.045/hour each)
- **ALB/NLB**: ~$0.0225/hour per load balancer
- **ECS**: Tasks run on Fargate (~$0.04/hour for minimal config)
- **ElastiCache**: cache.t4g.micro instances (~$0.016/hour)

**Tips to minimize costs:**
- Tests automatically destroy resources after completion
- Run specific tests instead of full suite during development
- Use smaller instance types in fixtures
- Monitor for orphaned resources if tests fail unexpectedly

## Troubleshooting

### Test Timeout

Increase the timeout if tests are failing due to time limits:

```bash
go test -v -timeout 90m ./...
```

### Resource Cleanup Failures

If `terraform destroy` fails, you may need to manually clean up:

1. Find resources with `terratest` tags in the AWS console
2. Delete resources in reverse dependency order
3. Check CloudWatch Logs, S3 buckets, and IAM roles

### AWS Permission Errors

Ensure your AWS credentials have permissions for:
- VPC, Subnet, Internet Gateway, NAT Gateway, Route Table
- Security Groups
- ALB, NLB, Target Groups, Listeners
- ECS Clusters, Services, Task Definitions
- ElastiCache Clusters, Replication Groups
- S3 Buckets
- CloudWatch Log Groups
- WAF WebACLs
- IAM Roles (for ECS task execution)

### Debugging Failed Tests

Run with verbose output:
```bash
go test -v -timeout 60m -run TestName ./... 2>&1 | tee test-output.txt
```

Check Terraform state:
```bash
cd test/fixtures/module/variant
tofu state list
tofu state show <resource>
```

## S3 Module Tests

The S3 module has comprehensive integration tests covering all documented use-cases from the README. The tests validate bucket creation, encryption, versioning, lifecycle rules, policy templates, and tag management.

### S3 Test Fixtures

| Fixture | Description | Key Features Tested |
|---------|-------------|---------------------|
| `basic/` | Basic S3 bucket with defaults | Bucket creation, SSE-S3 encryption, public access block |
| `with_kms/` | SSE-KMS encryption with bucket key | KMS key creation, SSE-KMS encryption, bucket key enabled |
| `with_versioning/` | Bucket versioning enabled | Versioning configuration and status |
| `with_lifecycle/` | Multiple lifecycle rules | Expiration, transitions, noncurrent version handling, multipart abort |
| `with_alb_logs_policy/` | ALB access logs policy template | Policy templates, ALB log delivery statements |
| `with_vpc_flow_logs_policy/` | VPC flow logs policy template | Policy templates, VPC flow log statements |
| `with_nlb_logs_policy/` | NLB access logs policy template | Policy templates, NLB log delivery statements |
| `with_custom_policy/` | Custom policy with template merging | Custom bucket policy, policy merging |
| `full/` | All features combined | Comprehensive validation of all S3 module features together |

### S3 Test Functions

| Test Function | Fixture | Description |
|---------------|---------|-------------|
| `TestS3Basic` | `basic/` | Basic bucket creation and default configuration |
| `TestS3WithKmsEncryption` | `with_kms/` | SSE-KMS encryption with bucket key enabled |
| `TestS3WithVersioning` | `with_versioning/` | Bucket versioning enabled |
| `TestS3WithLifecycle` | `with_lifecycle/` | Lifecycle configuration with multiple rules |
| `TestS3LifecycleTransitions` | `with_lifecycle/` | Storage class transitions (STANDARD_IA, GLACIER) |
| `TestS3LifecycleNoncurrentVersions` | `with_lifecycle/` | Noncurrent version expiration rules |
| `TestS3LifecycleMultipartAbort` | `with_lifecycle/` | Abort incomplete multipart uploads |
| `TestS3LifecycleExpiration` | `with_lifecycle/` | Object expiration rules |
| `TestS3WithAlbLogsPolicy` | `with_alb_logs_policy/` | ALB access logs policy statements |
| `TestS3WithVpcFlowLogsPolicy` | `with_vpc_flow_logs_policy/` | VPC flow logs policy statements |
| `TestS3WithNlbLogsPolicy` | `with_nlb_logs_policy/` | NLB access logs policy statements |
| `TestS3WithDenyInsecureTransport` | `with_alb_logs_policy/` | Deny insecure transport policy |
| `TestS3PublicAccessBlockSettings` | `basic/` | Public access block verification |
| `TestS3BucketTags` | `basic/` | Tag verification with AWS SDK |
| `TestS3WithCustomPolicy` | `with_custom_policy/` | Custom bucket policy statements |
| `TestS3PolicyMerging` | `with_custom_policy/` | Policy template and custom policy merging |
| `TestS3FullConfiguration` | `full/` | Comprehensive test of all features together |
| `TestS3ForceDestroy` | `basic/` | Force destroy with objects in bucket |

### Running S3 Tests

```bash
# Run all S3 tests
go test -v -timeout 60m -run TestS3 ./...

# Run specific S3 test
go test -v -timeout 30m -run TestS3WithKmsEncryption ./...

# Run only encryption-related tests
go test -v -timeout 30m -run "TestS3.*Kms|TestS3.*Encryption" ./...

# Run only lifecycle tests
go test -v -timeout 30m -run "TestS3.*Lifecycle" ./...

# Run only policy tests
go test -v -timeout 30m -run "TestS3.*Policy" ./...
```

### S3 Test Notes

- **KMS Key Management**: The `with_kms/` and `full/` fixtures create their own KMS keys for self-contained, repeatable tests. KMS keys use `deletion_window_in_days = 7` for cleanup.
- **Force Destroy**: All S3 fixtures use `force_destroy = true` to ensure cleanup even when buckets contain objects.
- **Parallel Execution**: S3 tests use unique bucket names to allow parallel execution without conflicts.
- **Policy Templates**: Tests verify policy statement SIDs to confirm correct policy template application.

## EKS Service Module Tests

The `compute/eks_service` module has two independent halves: the load balancer
wiring (target group + listener rule), gated on `listener_arn`, and an optional
ECR repository, gated on `ecr_repository_creation_enabled`. The tests cover
each half alone and both together.

No EKS cluster is provisioned. The module only creates the AWS-side plumbing
for a workload; the pods that register into the target group come from the
`rvn-eks-web` Helm chart, which is covered by `make test-charts`. Each fixture
therefore stands up only what the module needs: a VPC, and an ALB when a
listener is required.

### EKS Service Test Fixtures

| Fixture | Description | Key Features Tested |
|---------|-------------|---------------------|
| `with_alb/` | Web-shaped: listener set, ECR disabled | Target group, listener rule, health check, stickiness, deregistration delay, slow start, null `ecr_*` outputs |
| `worker/` | Worker/cron-shaped: no listener, ECR enabled | Null load balancer outputs, no target group in AWS, ECR name/scan-on-push/tag mutability/lifecycle policy |
| `with_alb_and_ecr/` | Both halves enabled | Target group and listener rule wired together alongside an ECR repository |
| `with_ecr_name_override/` | `ecr_repository_name` set | Repository takes the override rather than `var.name` |

### EKS Service Test Functions

| Test Function | Fixture | Description |
|---------------|---------|-------------|
| `TestEksServiceWithAlb` | `with_alb/` | Load balancer half fully configured, ECR outputs null |
| `TestEksServiceWorker` | `worker/` | Load balancer outputs null, ECR repository created |
| `TestEksServiceWithAlbAndEcr` | `with_alb_and_ecr/` | Both halves present and wired |
| `TestEksServiceEcrRepositoryNameOverride` | `with_ecr_name_override/` | Repository name override wins over `var.name` |

### Running EKS Service Tests

```bash
# All EKS service tests
make test FILTER=TestEksService

# A single test
make test-single TEST=TestEksServiceWorker

# Directly with go test
cd test && go test -v -timeout 30m -run TestEksService ./...
```

### EKS Service Test Notes

- **No NAT Gateways**: nothing runs in the private subnets, so all four
  fixtures set `nat_gateway_enabled = false`, keeping a run to a VPC (and two
  ALBs) for a few minutes.
- **Force delete on ECR**: every ECR-enabled fixture sets
  `ecr_force_delete_enabled = true` so `terraform destroy` succeeds even if
  an image was pushed during a run.
- **Null vs empty**: disabled outputs must be `null`, not `""`.
  `terraform.Output` renders a null as `"<nil>"`, so the tests compare the raw
  JSON via `terraform.OutputJson` (see `requireOutputNull`).
