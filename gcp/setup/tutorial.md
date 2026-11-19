# Connect a Google Cloud project to Ravion

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

## Before you start

You need permission to change IAM in the project: **Owner**, or **Project IAM
Admin** + **Service Account Admin** + **Workload Identity Pool Admin** +
**Role Administrator** + **Service Usage Admin**.

Keep Ravion's connect dialog open: it shows your **project id**, your
**connection id** (`gcpact_…`) and a one-time **onboarding token**.

## Select the project

```sh
gcloud config set project <walkthrough-project-id/>
```

## Review what will be created

```sh
terraform init
terraform plan \
  -var "project_id=$(gcloud config get-value project)" \
  -var "ravion_account_id=gcpact_REPLACE_ME" \
  -var "onboarding_token=REPLACE_ME"
```

The plan lists every role, service account and binding. The permissions Ravion
gets are listed in `catalog.gen.tf.json`; `README.md` explains each part.

To run your pipelines' Terraform with narrower rights than `roles/editor`, add
for example `-var 'runner_sa_roles=["roles/compute.admin","roles/storage.admin"]'`.

## Apply

```sh
terraform apply \
  -var "project_id=$(gcloud config get-value project)" \
  -var "ravion_account_id=gcpact_REPLACE_ME" \
  -var "onboarding_token=REPLACE_ME"
```

At the end Terraform reports the setup to Ravion. Ravion then checks the
connection on its own (it signs in and tests each permission); this can take a
few minutes while Google propagates the new IAM bindings. The connect dialog
updates when the project is connected.

## Keep the state

Terraform keeps its state in this directory. Keep it (for example copy
`terraform.tfstate` to a bucket, or configure a `gcs` backend) so you can
apply future Ravion setup versions or remove the setup with
`terraform destroy`.

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Ravion can now reach the project. When Ravion ships a new setup version, it
asks you to re-run `terraform apply` with the new version of this module.
