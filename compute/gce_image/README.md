# Compute Engine image

Creates what Compute Engine images are built with. Images are released only
through deploys of the `rvn-gcp-image` module definition: each deploy builds an
image on a builder VM from a parent image and ordered components, tests it on a
VM booted from it, publishes it when asked, and retires older images.

Google Cloud has no managed image builder, so a build is a VM the deploy drives
itself, the counterpart of the `compute/ami` module's EC2 Image Builder builds.

## What Terraform creates

- A builder service account. Every builder and test VM runs as it. It can write
  logs and read its own components, plus the roles and buckets you grant it.
- A private, versioned bucket holding one bash script per component, each named
  by a hash of its content.
- The project APIs builds need (Compute Engine, IAM, Cloud Storage), unless
  `enable_project_services` is off.

It creates no VM and no image. Applying the module never builds an image.

## What each deploy does

Each deploy is one release:

1. Boots a builder VM from the parent image as the builder service account,
   runs every component's build steps and then every component's validate
   steps, and powers the VM off.
2. Creates an image from the builder's boot disk and deletes the builder.
3. Boots a test VM from the image and runs every component's test steps. A
   failure deletes the image and fails the deploy. The test VM is deleted
   either way.
4. When `publish` is on, grants `roles/compute.imageUser` to
   `allAuthenticatedUsers` on the image and adds it to the image family.
5. Retires older images past the retention counts.

A redeploy or a rollback releases an earlier deploy's image again without
rebuilding it. Builder and test VMs are deleted when a deploy ends, whether it
succeeded, failed, or was cancelled.

## Components

A component is a list of named steps in three phases:

| Phase | Runs on | Use it for |
| --- | --- | --- |
| `build_steps` | the builder VM | Installing and configuring what the image carries |
| `validate_steps` | the builder VM, after every component's build steps | Checking the build before the image is taken |
| `test_steps` | a VM booted from the finished image | Checking what the image carries and nothing else |

A step runs its `commands` in order as one bash script with
`set -euo pipefail` and stdin closed, so the phase stops at the first command
that exits non-zero. `timeout_seconds` stops a step that runs too long.

The module writes each component into one script,
`gs://<component_bucket>/components/<name>-<hash>.sh`, that runs one phase:

```bash
bash app-0123456789abcdef.sh build    # or validate, or test
```

Every step is embedded base64-encoded, so no command can break the script's
quoting. The script prints `gce-image: <phase> step <name> started` before each
step and `gce-image: <phase> step <name> failed with exit <code>` when one fails,
then exits with that code. Copy a script to a VM of your own and run it to debug
a component.

A changed component is a new script beside the old one, and the next deploy
builds with it. The bucket is versioned: a replaced script stays readable by its
generation for `component_retention_days`, so a build that started before an
apply still finishes with the script it was given.

The builder and test VMs run the scripts through the Google guest environment's
startup scripts. Build on a parent image that ships the guest environment, as
every Google-published image does, and keep it in the image if its test steps
should run.

## Parameters

Put the values that change between releases, such as a release version, in
`parameter_definitions`. A step reads one as an environment variable of the same
name, so parameter names are shell variable names:

```hcl
parameter_definitions = [
  { name = "ReleaseVersion", value = "v1.2.3" },
  { name = "Channel", default = "stable" },
]
build_steps = [
  { name = "Install", commands = ["curl -fsSLo /usr/local/bin/app https://releases.example.com/$ReleaseVersion/app"] },
]
```

A parameter's `value` is passed by each deploy, and a deploy's
`component_parameters` override it. A parameter neither sets takes its
`default`; one with neither stays unset, and a step that reads it fails.
`component_refs` carries each component's values to the deploy, so a new release
never needs an apply.

## Public images

Images are global: one image boots VMs in every region, so there are no copies
to make. Publishing grants `roles/compute.imageUser` to `allAuthenticatedUsers`
on each published image, never on the project, so unpublished images stay
private and never join the family.

- An organization that enforces domain restricted sharing
  (`iam.allowedPolicyMemberDomains`) refuses that grant. Build in a project
  where the constraint is not enforced.
- A project that boots the image and enforces trusted image projects
  (`compute.trustedImageProjects`) must allow this project.
- `nested_virtualization` needs a project where
  `compute.disableNestedVirtualization` is not enforced.
- Labels and the description of a public image are visible to everyone who can
  use it. Keep anything private out of them.

## Retention

Each deploy keeps the newest `retention_published_image_count` images (5 by
default) public, and the next `retention_private_image_count` (10 by default)
private. Older published images lose public access, leave the family, and are
marked deprecated with the new release as their replacement. Images past both
counts are deleted. Both are inputs of the module definition rather than
Terraform variables, because only the deploy reads them.

Destroying the module deletes the builder service account and the component
bucket. It never deletes images, which VMs and other projects may still use.

## Usage

```hcl
module "image" {
  source = "git::https://github.com/ravionhq/modules.git//compute/gce_image?ref=v1.0.0"

  name       = "app-image"
  project_id = "acme-images"
  region     = "us-central1"

  components = [
    {
      name = "provision"

      parameter_definitions = [
        { name = "ReleaseVersion", value = "v1.2.3" },
      ]

      build_steps = [
        {
          name = "InstallRelease"
          commands = [
            "gcloud storage cp gs://acme-releases/$ReleaseVersion/app /usr/local/bin/app",
            "chmod 0755 /usr/local/bin/app",
          ]
        },
      ]

      test_steps = [
        { name = "AppRuns", commands = ["/usr/local/bin/app --version"], timeout_seconds = 60 },
      ]
    },
  ]

  builder_bucket_readers = ["acme-releases"]
}
```

A deploy reads `project_id`, `zone`, `builder_service_account_email`,
`component_refs`, `network_self_link`, `subnetwork_self_link` and `labels` from
the outputs. The parent image, machine type, boot disk, nested virtualization,
external IP, image family, guest OS features, storage locations and retention
are module definition inputs the deploy reads directly.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| google | >= 8.1 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Prefix of the builder service account, the component bucket, and every builder VM and image name. 1-40 characters | `string` | n/a | yes |
| project_id | Project images are built and stored in | `string` | n/a | yes |
| region | Region of the component bucket and the build zone | `string` | n/a | yes |
| zone | Zone builds run in. Null picks the first zone of the region that is up | `string` | `null` | no |
| components | Components each build runs, in order: `name`, optional `description`, `parameter_definitions` (`name`, `value`, `default`, `description`), and `build_steps`/`validate_steps`/`test_steps` (`name`, `commands`, `timeout_seconds`) | `list(object)` | n/a | yes |
| component_retention_days | Days a replaced component script stays readable | `number` | `30` | no |
| network | VPC network for the builder and test VMs. Ignored with `subnetwork` | `string` | `"default"` | no |
| subnetwork | Subnetwork of the region for the builder and test VMs | `string` | `null` | no |
| network_project_id | Project owning the network or subnetwork, for a Shared VPC | `string` | `null` | no |
| builder_roles | Project roles for the builder service account | `list(string)` | `[]` | no |
| builder_bucket_readers | Buckets the builder service account may read | `list(string)` | `[]` | no |
| deployer_members | Principals granted `roles/iam.serviceAccountUser` on the builder service account | `list(string)` | `[]` | no |
| enable_project_services | Enable the Compute Engine, IAM and Cloud Storage APIs | `bool` | `true` | no |
| labels | Labels for every resource and image, rewritten to label syntax | `map(string)` | `{}` | no |
| module_instance_id | Id of the Ravion module instance. Ravion sets it | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| name | Name prefix of the builder VMs and images |
| project_id | Project images are built and stored in |
| region | Region of the component bucket |
| zone | Zone builds run in |
| labels | Labels every image carries, in label syntax |
| builder_service_account_email | Service account the builder and test VMs run as |
| component_bucket | Bucket holding the component scripts |
| component_refs | Every component in run order, as `{name, url, generation, sha256, parameters}` |
| network_self_link | Network the builder and test VMs attach to |
| subnetwork_self_link | Subnetwork they attach to, or null for an auto mode network's own |
| module_instance_id | Id of the Ravion module instance these resources belong to |

## Testing

```bash
tofu init -backend=false
tofu test
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
```

The Python tests render real component scripts and run them with bash.
