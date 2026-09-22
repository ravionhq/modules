# EC2 Image Builder

Creates an EC2 Image Builder pipeline that bakes an AMI from a parent image and
ordered components, and distributes it across regions — privately, to selected
accounts, or publicly.

The module creates the components, the recipe, the infrastructure configuration
and its build instance role, the distribution configuration, and the pipeline.

The pipeline builds on a schedule, on request from a CI step, or during an
apply that changes the recipe. The request path is what a release pipeline
uses: the step starts the build, waits for the image, and reads the new AMI id.

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
      name = "provision"

      parameter_definitions = [
        { name = "ReleaseVersion", default = "v1.2.3", value = "v1.2.3" },
      ]

      build_steps = [
        {
          name = "InstallRelease"
          commands = [
            "set -euo pipefail",
            "aws s3 cp s3://example-releases/{{ ReleaseVersion }}/app /usr/local/bin/app",
            "chmod 0755 /usr/local/bin/app",
          ]
        },
      ]

      validate_steps = [
        { name = "AppRuns", commands = ["/usr/local/bin/app --version"] },
      ]
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

  schedule_expression              = "cron(0 3 ? * SUN *)"
  create_pipeline_execution_policy = true
}
```

Start a build by hand:

```bash
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <pipeline_arn>
```

## Components

Components run in the order listed. Each one names where its document comes
from in `source`:

| `source` | What the component sets | When it fits |
| --- | --- | --- |
| `steps` | `build_steps`, `validate_steps`, `test_steps` and `parameter_definitions` | Most components. The module writes the document. |
| `document` | `data` | A document you already have, or an action the step fields do not cover |
| `arn` | `arn` | An AWS-managed component, or one that already exists in the account |

A caller that leaves `source` out is read by what it filled in.

A step names an action and what that action needs. `ExecuteBash` and
`ExecutePowerShell` take `commands`, run in order; the phase stops at the first
one that exits non-zero. Every other action takes `inputs_json`, the JSON its
AWS documentation describes, and an action that needs none leaves it out:

```hcl
build_steps = [
  {
    name        = "Fetch"
    action      = "S3Download"
    inputs_json = jsonencode([{ source = "s3://releases/runner", destination = "/tmp/runner" }])
  },
  {
    name            = "Install"
    commands        = ["install -m 0755 /tmp/runner /usr/local/bin/runner"]
    timeout_seconds = 600
    max_attempts    = 2
  },
  { name = "Restart", action = "Reboot" },
]
```

A phase with no steps is left out of the document, and so is a step field left
blank.

## Building on a schedule

`schedule_expression` runs the pipeline unattended. With the default
`schedule_start_condition`, a scheduled run builds only when the parent image or
a wildcard-versioned component has an update, so a weekly schedule on a
`parent_image_lookup` recipe rebuilds when the upstream AMI moves and stays idle
otherwise.

## Building from a pipeline step

`create_pipeline_execution_policy = true` creates a customer-managed policy that
starts this pipeline and reads the images it produces, and nothing else. Its ARN
is the `pipeline_execution_policy_arn` output. A Ravion `custom` step attaches
that ARN under `infrastructure.permissions.attach`, starts the pipeline, polls
`list-image-pipeline-images` until the image is `AVAILABLE`, and publishes the
AMI id for later steps:

```yaml
- id: build_ami
  name: Build AMI
  type: custom
  timeout: 7200
  infrastructure:
    type: ec2
    instance_size: small
    aws_account_id: my-aws-account
    region: us-west-2
    permissions:
      attach:
        - arn:aws:iam::123456789012:policy/app-host-start-image-pipeline
  environment_variables:
    AWS_REGION: us-west-2
    PIPELINE_ARN: arn:aws:imagebuilder:us-west-2:123456789012:image-pipeline/app-host
  outputs:
    - ami_id
  commands:
    - |
      set -euo pipefail

      BUILD_ARN=$(aws imagebuilder start-image-pipeline-execution \
        --image-pipeline-arn "$PIPELINE_ARN" \
        --query imageBuildVersionArn --output text)

      while true; do
        STATE=$(aws imagebuilder list-image-pipeline-images \
          --image-pipeline-arn "$PIPELINE_ARN" \
          --query "imageSummaryList[?arn=='$BUILD_ARN'].state.status | [0]" --output text)
        case "$STATE" in
          AVAILABLE) break ;;
          FAILED|CANCELLED) echo "Image build $STATE" >&2; exit 1 ;;
        esac
        sleep 60
      done

      AMI_ID=$(aws imagebuilder list-image-pipeline-images \
        --image-pipeline-arn "$PIPELINE_ARN" \
        --query "imageSummaryList[?arn=='$BUILD_ARN'].outputResources.amis[0].image | [0]" --output text)
      echo "ami_id=$AMI_ID" >> "$RAVION_OUTPUT"
```

A later step reads the image as `<< steps.build_ami.output.ami_id >>` — to pin a
launch template, to hand to a `terraform:apply` step, or to publish elsewhere.
Give the step a timeout longer than a build takes; a build commonly runs 20-60
minutes. `build_timeout_minutes` covers the same wait for `build_on_apply`.

The policy grants `StartImagePipelineExecution`, `GetImagePipeline` and
`ListImagePipelineImages` on this pipeline, and `GetImage` on the images it
produces.

## Immutable recipes and components

Image Builder recipes and components cannot be updated, only versioned. This
module names each by a hash of its content instead: a changed document is a new
component beside the old one, the recipe that uses it is a new recipe, and the
pipeline moves to it in the same apply. The old ones are deleted once nothing
references them. `recipe_version` never has to change for an apply to succeed.

Put the values that change between builds — a release version, a checksum — in
`parameter_definitions`, which a step reads as `{{ ParameterName }}`. A
parameter's `value` is passed by the recipe rather than written into the
document, so a changed value is a new recipe over the same component. A
`document` or `arn` component passes the same values through `parameters`.

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
- A public image cannot be backed by an encrypted snapshot, and AWS refuses to
  publish one an hour into the build. The module settles that at plan time
  instead. `root_volume` encryption defaults to off when `public` is true, and
  an explicit `encrypted = true` is refused. The parent image must be an AMI
  this account can describe — an `ami-` id or a `parent_image_lookup` — whose
  snapshots are unencrypted, because every image inherits them. EBS encryption
  by default must be off in the build region and every distribution region,
  since the account setting overrides the recipe and encrypts the copies too.
- Tags are visible only to the owning account, even on a public image. Other
  accounts find the image by owner and name.

## Build logs

`log_bucket` sends the build logs to S3 and grants the build instance write
access to exactly the prefix they land under. An empty `log_prefix` writes them
at the bucket root.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the pipeline, and the prefix of every other resource this module creates | `string` | n/a | yes |
| components | Components the recipe runs, in order. Each sets `source` (`steps`, `document` or `arn`) and the fields it names: `build_steps`/`validate_steps`/`test_steps` and `parameter_definitions`, `data`, or `arn`. Optional `description`, `platform`, `parameters` | `list(object)` | n/a | yes |
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
| log_prefix | Key prefix for build logs. Empty writes them at the bucket root | `string` | `"image-builder"` | no |
| create_pipeline_execution_policy | Create a policy that starts this pipeline and reads its images | `bool` | `false` | no |
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
| build_timeout_minutes | How long an apply waits for a `build_on_apply` build | `number` | `image_tests_timeout_minutes + 60` | no |

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
| pipeline_execution_policy_arn | The ARN of the policy that starts this pipeline and reads its images |

## Testing

```bash
tofu init -backend=false
tofu test
```
