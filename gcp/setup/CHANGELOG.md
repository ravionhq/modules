# Ravion GCP project setup — changelog

Customer-facing. Each entry says what Ravion can do in the project after
running that version, in plain words. The newest version is at the top and
must match `VERSION`.

## 1.0.1

- Sandbox hosts (`ravion-sandbox-host`) may mint short-lived `ravion-runner`
  tokens for the steps and sandboxes they run
  (`roles/iam.serviceAccountTokenCreator` on `ravion-runner` only).
- Ravion may upload objects (`storage.objects.create`) to the Cloud Storage
  buckets it manages for sandbox pools, alongside the reads and deletes it
  already had.

## 1.0.0

First release.

- Lets Ravion sign in to the project with workload identity federation from
  `https://oidc.ravion.com`. No service account keys are created or shared.
- Creates five service accounts Ravion impersonates, one per kind of work:
  `ravion-read` (inventory, logs, metrics, images), `ravion-ops` (secrets,
  log/metric writes, artifact uploads), `ravion-compute` (runner VMs),
  `ravion-sandbox` (sandbox hosts, their buckets and firewall rules) and
  `ravion-deploy` (preparing the project for Terraform runs). Each holds a
  custom role `ravion_<tier>` with only the permissions listed in
  `catalog.gen.tf.json`.
- Creates `ravion-runner`, the identity of the VMs that run your pipelines and
  Terraform (`roles/editor` by default, set with `runner_sa_roles`), and
  `ravion-sandbox-host`, the identity of sandbox hosts.
- Enables the APIs Ravion calls.
