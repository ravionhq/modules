# AMI

Creates the EC2 Image Builder infrastructure an AMI is baked on. Images are
released only through deploys of the `rvn-aws-ami` module definition:
each deploy builds an AMI from a parent image and ordered components, copies it
to every region, publishes it when asked, and retires older images.

## What Terraform creates

- The components, each created from steps or a document, or referenced by ARN.
- The build instance IAM role and instance profile, with the two policies Image
  Builder needs plus whatever you grant the components.
- The infrastructure configuration a build runs on: instance types, subnet,
  security groups, IMDSv2, and optional S3 build logs.
- A distribution configuration that covers the build region only and grants no
  launch permission. It names and tags each image a build produces and leaves
  it private.

It creates no image recipe, image pipeline, or image. Applying the module never
builds an AMI.

## What each deploy does

Each deploy is one release:

1. Creates an image recipe from the parent image, the components in order and
   this deploy's component parameters, then builds it in the build region on a
   temporary build instance. The components' test phases run on an instance
   launched from the new image.
2. Copies the new AMI to every additional region.
3. Tags every image and snapshot it created.
4. Grants launch permission `all` on the images in every region when `publish`
   is on.
5. Retires older images in each region past the retention counts.

A redeploy or a rollback releases an earlier deploy's images again without
rebuilding them.

## Deploying from a pipeline

A `deploy` step releases a new image. A build commonly takes 20-60 minutes, and
the deploy finishes once every copy is available.

```yaml
- id: release_image
  name: Release image
  type: deploy
  module_instance: << pipeline.variant.id >>.app-image
  input:
    component_parameters:
      provision:
        ReleaseVersion: << steps.build_app.output.version >>
    extra_tags:
      release: << steps.build_app.output.version >>
    publish: true
```

| Input | Default | What it does |
| --- | --- | --- |
| `component_parameters` | `{}` | Parameter values for this deploy, as `{component: {parameter: value}}`. Each overrides the value the component sets in the module, key by key. |
| `extra_tags` | `{}` | Tags added to every AMI and snapshot this deploy creates, in every region. |
| `publish` | `false` | Grants launch permission `all` on this deploy's AMIs in every region. `false` keeps them private. |

A deploy can also be started from the dashboard or with `ravion deploy create`.

## Retention

Each deploy keeps the newest `retention_published_image_count` images (5 by
default) public in each region, and the next `retention_private_image_count`
(10 by default) private. Older published images are made private, and images
past both counts are deregistered along with their snapshots. Both are inputs
of the module definition rather than Terraform variables, because only the
deploy reads them.

AWS allows 5 public AMIs per region by default, and the quota counts every
public AMI the account owns in that region, not only the images this module
releases. A deploy with `publish` on fails in a region at its quota, so keep
`retention_published_image_count` within what the account allows, and request a
higher quota before raising it.

## Public images

- New accounts block public AMI sharing per region, and a deploy with `publish`
  on fails in a region that still blocks it. Turning the block off covers every
  AMI the account owns in that region, not one image:

  ```bash
  aws ec2 disable-image-block-public-access --region <region>
  ```
- A public image cannot be backed by an encrypted snapshot. Publish images built
  on an unencrypted parent image, in regions where EBS encryption by default is
  off.
- Tags are visible only to the owning account, even on a public image. Other
  accounts find the image by owner and name.

## Usage

```hcl
module "image" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ami?ref=v1.0.0"

  name = "app-image"

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
      Resource = "arn:aws:s3:::example-releases/*"
    }]
  })

  ami_tags = { app = "example" }
}
```

A deploy reads `region`, `infrastructure_configuration_arn`,
`distribution_configuration_arn` and `component_refs` from the outputs.

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
    inputs_json = jsonencode([{ source = "s3://example-releases/app", destination = "/tmp/app" }])
  },
  {
    name            = "Install"
    commands        = ["install -m 0755 /tmp/app /usr/local/bin/app"]
    timeout_seconds = 600
    max_attempts    = 2
  },
  { name = "Restart", action = "Reboot" },
]
```

A phase with no steps is left out of the document, and so is a step field left
blank.

## Parameters and immutable components

Put the values that change between releases — a release version, a checksum —
in `parameter_definitions`, which a step reads as `{{ ParameterName }}`. A
parameter's `value` is passed by each deploy's image recipe rather than written
into the document, and a deploy's `component_parameters` override it, so a new
release never needs a new component. A `document` or `arn` component passes the
same values through `parameters`. `component_refs` carries each component's
values to the deploy.

Image Builder components cannot be updated, only versioned. This module names
each by a hash of its content instead: a changed document is a new component
beside the old one, and the next deploy builds with it. `component_version`
never has to change for an apply to succeed.

## Parent image

`parent_image` pins one image: an AMI id, an Image Builder image ARN, or
`ssm:<parameter>`. `parent_image_lookup` names the newest AMI an owner publishes
under a name pattern, and each deploy looks it up again when it starts, so a
newer parent image reaches the next deploy without an apply. The `parent_image`
output reports the image given, or the lookup's match at apply time, and an
apply with neither fails.

Image Builder drives the build instance through the Systems Manager agent, and
installs it on the distributions it supports. Build on a parent image that ships
the agent or that Image Builder can install it on.

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
| name | Name of the configurations, and the prefix of every other resource this module creates | `string` | n/a | yes |
| components | Components each build runs, in order. Each sets `source` (`steps`, `document` or `arn`) and the fields it names: `build_steps`/`validate_steps`/`test_steps` and `parameter_definitions`, `data`, or `arn`. Optional `description`, `platform`, `parameters` | `list(object)` | n/a | yes |
| description | Description stored on the infrastructure and distribution configurations | `string` | `null` | no |
| region | Region images are built in | `string` | provider region | no |
| tags | A map of tags to assign to resources | `map(string)` | `{}` | no |
| parent_image | AMI id, Image Builder image ARN, or `ssm:<parameter>` | `string` | `null` | one of the two |
| parent_image_lookup | Newest AMI by `owners`, `name` pattern and `architecture` | `object` | `null` | one of the two |
| component_version | Semantic version of the created components | `string` | `"1.0.0"` | no |
| instance_types | Instance types a build may run on, in order of preference | `list(string)` | `["m7i.large"]` | no |
| subnet_id | Subnet for the build instance. Null uses the default VPC | `string` | `null` | no |
| security_group_ids | Security groups for the build instance. Required with `subnet_id` | `list(string)` | `[]` | no |
| terminate_instance_on_failure | Terminate the build instance when a build fails | `bool` | `true` | no |
| instance_managed_policy_arns | Managed policies for the build instance role, beyond the two Image Builder needs | `list(string)` | `[]` | no |
| instance_policy_json | Inline IAM policy for the build instance role | `string` | `null` | no |
| log_bucket | S3 bucket for build logs | `string` | `null` | no |
| log_prefix | Key prefix for build logs. Empty writes them at the bucket root | `string` | `"image-builder"` | no |
| ami_name | Image name. Must contain `{{ imagebuilder:buildDate }}` or `{{ imagebuilder:buildVersion }}` | `string` | `<name>-{{ imagebuilder:buildDate }}` | no |
| ami_description | Description stored on each image built, in the build region | `string` | `null` | no |
| ami_tags | Tags written on each image built, in the build region | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| region | The region images are built in |
| parent_image | The parent image given, or the lookup's match at apply time |
| component_refs | Every component this module creates or references, in run order, as `{name, arn, parameters}` |
| infrastructure_configuration_arn | The ARN of the infrastructure configuration a build runs on |
| distribution_configuration_arn | The ARN of the build-region distribution configuration |
| instance_role_arn | The ARN of the build instance's IAM role |
| instance_role_name | The name of the build instance's IAM role |

## Testing

```bash
tofu init -backend=false
tofu test
```
