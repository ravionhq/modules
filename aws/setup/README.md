# Ravion AWS account setup (Terraform)

Connects one AWS account to Ravion with **OIDC federation**, as a Terraform
module. It is the alternative to Ravion's CloudFormation template for teams
that manage their infrastructure with Terraform or OpenTofu: both create the
same roles with exactly the same permissions, and Ravion offers both when you
connect an account. Use one or the other for a Ravion connection, not both:
they create roles with the same names.

No access keys are created or shared. Ravion's credentials broker signs a
short-lived token with `https://oidc.ravion.com`, AWS STS exchanges it for
temporary credentials of one of the roles this module creates, and the
broker scopes every session to the work it is for.

Version: [`VERSION`](VERSION) · Changes: [`CHANGELOG.md`](CHANGELOG.md) ·
Roles and policies: [`iam.gen.tf.json`](iam.gen.tf.json) (generated,
do not edit).

## Usage

Ravion's connect dialog (**Settings → AWS accounts → Connect**, then
**Terraform**) shows this block with your values filled in:

```hcl
module "ravion" {
  source = "git::https://github.com/ravionhq/modules.git//aws/setup?ref=rvn-aws-setup@<version>"

  ravion_id        = "<your AWS account's id in Ravion>"
  onboarding_token = var.ravion_onboarding_token

  # Optional: the products you use (all default to true).
  # enable_deployments = true
  # enable_terraform   = true
  # enable_sandboxes   = true
}

variable "ravion_onboarding_token" {
  type      = string
  sensitive = true
}
```

Apply it with credentials that can manage IAM in the account (the AWS
provider configured as usual; IAM is global, so any region works). At the end
the module reports the roles to Ravion, which checks it can assume each of
them before it marks the account connected.

| Variable             | Default | Purpose                                                                                                                                                            |
| -------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ravion_id`          |         | Your AWS account's id in Ravion. The roles are named `rvn-<ravion_id>` and trust only tokens Ravion issues for this id.                                            |
| `onboarding_token`   |         | From the connect dialog. Only sent to `callback_url`; it grants nothing in your account.                                                                           |
| `enable_deployments` | `true`  | Create the deployments role.                                                                                                                                       |
| `enable_terraform`   | `true`  | Create the Terraform role, the only one that can give a pipeline step `AdministratorAccess`.                                                                       |
| `enable_sandboxes`   | `true`  | Create the CI pipelines, GitHub runners and sandboxes role (also created when deployments or Terraform are enabled).                                               |
| `oidc_provider_arn`  | `""`    | An existing IAM OIDC provider for `https://oidc.ravion.com`. An account holds one provider per issuer: set this when another Ravion connection already created it. |
| `callback_url`       | Ravion  | Where the setup reports to.                                                                                                                                        |
| `send_callback`      | `true`  | Report the setup to Ravion. Ravion does not use the roles until it has the report.                                                                                 |

## What it creates

| Resource                                                                             | Purpose                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| IAM OIDC provider for `https://oidc.ravion.com`                                      | Lets the roles trust Ravion's tokens (unless `oidc_provider_arn` names an existing one).                                                                                                  |
| Role `rvn-<ravion_id>` and policies `rvn-<ravion_id>-broker`, `-deploy`, `-deploy-2` | Account-wide work: regions, networks, quotas and the broker's session permissions.                                                                                                        |
| Roles `rvn-<ravion_id>-deployments`, `-terraform`, `-sandboxes` and their policies   | One role per product you enable. Each holds only the permissions of that product.                                                                                                         |
| Inline policy `RavionPolicy` on every role                                           | `EnforceBrokerSourceIp` denies any call that does not come from Ravion's credentials broker. `ProtectRavionStackRoles` stops a Ravion role from changing Ravion's own roles and policies. |
| Trust policy of every role                                                           | Only Ravion's issuer, only tokens for this `ravion_id`, only from the broker's addresses.                                                                                                 |
| `terraform_data.callback`                                                            | `curl`s `callback_url` with `Authorization: Bearer <onboarding_token>` and the role ARNs and version. Re-runs whenever they change.                                                       |
| `terraform_data.disconnect`                                                          | On `terraform destroy`, tells Ravion the roles are going away before they are deleted. Best effort.                                                                                       |

The callback body:

```json
{
  "event": "apply",
  "ravion_id": "…",
  "aws_account_id": "123456789012",
  "role_arn": "arn:aws:iam::123456789012:role/rvn-…",
  "deployments_role_arn": "arn:aws:iam::123456789012:role/rvn-…-deployments",
  "terraform_role_arn": "arn:aws:iam::123456789012:role/rvn-…-terraform",
  "sandboxes_role_arn": "arn:aws:iam::123456789012:role/rvn-…-sandboxes",
  "role_version": "1.0.72"
}
```

A disabled product's role is reported as `""`.

## Versions

Each version is tagged `rvn-aws-setup@<version>` in this repository. The
version is Ravion's role version: Ravion's CloudFormation template of the
same version grants exactly the same permissions, and
[`CHANGELOG.md`](CHANGELOG.md) says what each version changes. When Ravion
shows that an update is available, change `ref=` in `source` to the new tag
(the dialog shows the block with a fresh onboarding token) and apply. Diff
the two tags, or run `terraform plan`, to see what changes.

The destroy-time report keeps the onboarding token in the Terraform state,
like the other variables; protect the state as you would for any IAM change.

## Uninstalling

`terraform destroy` reports the disconnection to Ravion and removes
everything, after which Ravion can no longer reach the account.
