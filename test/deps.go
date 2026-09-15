// Package test provides Terratest integration tests for the modules.
// This file imports dependencies to ensure they are included in go.mod.
package test

import (
	// AWS SDK v2 dependencies
	_ "github.com/aws/aws-sdk-go-v2"
	_ "github.com/aws/aws-sdk-go-v2/config"
	_ "github.com/aws/aws-sdk-go-v2/service/ec2"
	_ "github.com/aws/aws-sdk-go-v2/service/ecr"
	_ "github.com/aws/aws-sdk-go-v2/service/ecs"
	_ "github.com/aws/aws-sdk-go-v2/service/elasticache"
	_ "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"

	// Terratest
	_ "github.com/gruntwork-io/terratest/modules/terraform"

	// Testify assertions
	_ "github.com/stretchr/testify/assert"
	_ "github.com/stretchr/testify/require"
)
