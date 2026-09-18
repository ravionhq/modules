# EC2 Image Builder

Creates an EC2 Image Builder pipeline that bakes an AMI from a parent image and
ordered components, and distributes it across regions — privately, to selected
accounts, or publicly.

The module creates the components, the recipe, the infrastructure configuration
and its build instance role, the distribution configuration, and the pipeline.
It can also build an image during apply.

## Usage

```hcl
module "image" {
  source = "git::https://github.com/ravionhq/modules.git//compute/image_builder?ref=v1.0.0"

  name = "app-host"

  parent_image_lookup = {
    owners = ["amazon"]
    name   = "al2023-ami-2023.*-x86_64"
  }

  components = [
    {
      name       = "provision"
      data       = file("${path.module}/provision.yml")
      parameters = { ReleaseVersion = "v1.2.3" }
    },
  ]

  instance_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::example-releases/v1.2.3/*"
    }]
  })

  root_volume = {
    device_name = "/dev/xvda"
    size_gb     = 30
  }

  ami_tags             = { release = "v1.2.3" }
  distribution_regions = ["us-east-1", "eu-west-1"]
  public               = true
}
```

Start a build:

```bash
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <pipeline_arn>
```

## Immutable recipes and components

Image Builder recipes and components cannot be updated, only versioned. This
module names each by a hash of its content instead: a changed document is a new
component beside the old one, the recipe that uses it is a new recipe, and the
pipeline moves to it in the same apply. The old ones are deleted once nothing
references them. `recipe_version` never has to change for an apply to succeed.

Put the values that change between builds — a release version, a checksum — in
component `parameters`. A changed parameter is a new recipe over the same
component.

With `parent_image_lookup`, the parent image id is resolved at plan time. An
apply after the owner publishes a newer image produces a new recipe.

## The Systems Manager agent

Image Builder drives the build instance through the Systems Manager agent. On
the distributions it supports it installs the agent itself, and removes it
afterwards when `ssm_agent_uninstall_after_build` is true.

Supplying `user_data` replaces that install script, so on a parent image that
ships without the agent the user data must install it. An agent installed that
way stays on the image; a component that does not want it running on every boot
can `systemctl disable` it as its last build step. Image tests launch a fresh
instance from the image and reach it the same way, so set
`image_tests_enabled = false` for an image that does not start the agent.

## Public images

`public = true` adds the `all` launch group in every region an image lands in.

- New accounts block public AMI sharing per region. With
  `manage_image_block_public_access` (the default) the module turns the block
  off in the build region and every distribution region. The setting is
  account-wide for the region, and destroying the module leaves it off.
- A public image cannot be backed by an encrypted snapshot. `root_volume`
  encryption defaults to off when `public` is true, and the module refuses an
  explicit `encrypted = true`. EBS encryption by default must also be off in
  the build region, or the snapshot is encrypted regardless.
- Tags are visible only to the owning account, even on a public image. Other
  accounts find the image by owner and name.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the pipeline, and the prefix of every other resource this module creates | `string` | n/a | yes |
| components | Components the recipe runs, in order. Each sets `data` (inline document) or `arn` (existing component); `source` (`inline` or `arn`) picks one when both are present. Optional `description`, `platform`, `parameters` | `list(object)` | n/a | yes |
| description | Description stored on the pipeline, the recipe and the configurations | `string` | `null` | no |
| region | Region the image is built in | `string` | provider region | no |
| tags | A map of tags to assign to resources | `map(string)` | `{}` | no |
| recipe_version | Semantic version of the recipe and the created components | `string` | `"1.0.0"` | no |
| parent_image | AMI id, Image Builder image ARN, or `ssm:<parameter>` | `string` | `null` | one of the two |
| parent_image_lookup | Newest AMI by `owners`, `name` pattern and `architecture` | `object` | `null` | one of the two |
| user_data | Plain-text user data for the build instance. Replaces the Systems Manager agent install | `string` | `null` | no |
| working_directory | Working directory for the build and test workflows | `string` | `null` | no |
| ssm_agent_uninstall_after_build | Remove the agent Image Builder installed for the build | `bool` | `true` | no |
| root_volume | `device_name`, `size_gb`, and optional `type`, `iops`, `throughput`, `encrypted`, `kms_key_id`. The snapshot size is the smallest root volume an instance can launch with | `object` | `null` | no |
| instance_types | Instance types the build may run on, in order of preference | `list(string)` | `["m7i.large"]` | no |
| subnet_id | Subnet for the build instance. Null uses the default VPC | `string` | `null` | no |
| security_group_ids | Security groups for the build instance. Required with `subnet_id` | `list(string)` | `[]` | no |
| terminate_instance_on_failure | Terminate the build instance when a build fails | `bool` | `true` | no |
| instance_managed_policy_arns | Managed policies for the build instance role, beyond the two Image Builder needs | `list(string)` | `[]` | no |
| instance_policy_json | Inline IAM policy for the build instance role | `string` | `null` | no |
| log_bucket | S3 bucket for build logs | `string` | `null` | no |
| log_prefix | Key prefix for build logs | `string` | `"image-builder"` | no |
| ami_name | Image name. Must contain `{{ imagebuilder:buildDate }}` or `{{ imagebuilder:buildVersion }}` | `string` | `<name>-{{ imagebuilder:buildDate }}` | no |
| ami_description | Description stored on each image | `string` | `null` | no |
| ami_tags | Tags written on each image, in every region | `map(string)` | `{}` | no |
| distribution_regions | Regions the image is copied to, beyond the build region | `list(string)` | `[]` | no |
| public | Make every image launchable by any AWS account | `bool` | `false` | no |
| manage_image_block_public_access | When public, unblock public AMI sharing in every region an image lands in | `bool` | `true` | no |
| launch_account_ids | Accounts granted launch permission | `list(string)` | `[]` | no |
| launch_organization_arns | Organizations granted launch permission | `list(string)` | `[]` | no |
| pipeline_enabled | Whether the pipeline can run | `bool` | `true` | no |
| schedule_expression | Cron expression the pipeline runs on. Null is manual | `string` | `null` | no |
| schedule_start_condition | Whether a scheduled run always builds or only on dependency updates | `string` | `"EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"` | no |
| image_tests_enabled | Launch a test instance and run the components' test phases | `bool` | `true` | no |
| image_tests_timeout_minutes | How long the test phase may run | `number` | `60` | no |
| enhanced_image_metadata_enabled | Collect package and other metadata from each image | `bool` | `true` | no |
| build_on_apply | Build an image during apply, and again whenever the recipe changes | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| region | The region the image is built in |
| pipeline_arn | The ARN of the image pipeline |
| pipeline_name | The name of the image pipeline |
| recipe_arn | The ARN of the current image recipe |
| recipe_name | The name of the current image recipe |
| parent_image | The parent image the current recipe builds on |
| component_arns | ARNs of the created components, keyed by component name |
| component_names | Names of the created components, keyed by component name |
| infrastructure_configuration_arn | The ARN of the infrastructure configuration |
| distribution_configuration_arn | The ARN of the distribution configuration |
| distribution_regions | Every region an image is produced in |
| instance_role_arn | The ARN of the build instance's IAM role |
| instance_role_name | The name of the build instance's IAM role |
| image_arn | The ARN of the image built during apply |
| ami_ids | AMI ids of the image built during apply, keyed by region |

## Testing

```bash
tofu init -backend=false
tofu test
```
