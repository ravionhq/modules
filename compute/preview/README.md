# Preview Module

This directory holds the `rvn-preview` module definition: a preview of a repository's branches. Each branch runs in its own sandbox from shell steps, and its HTTP ports are served through a [preview ingress](../../networking/preview_ingress).

The module has no Terraform. It creates no AWS resources and has no stack, build or deploy. Its definition maps the module's inputs into a `preview` block, which Ravion reads on every deploy and every resume of a preview.

## Requirements

| Requirement | Purpose |
| --- | --- |
| An execution environment with a sandbox pool | Runs the sandboxes |
| An `rvn-preview-ingress` module instance in the same environment, for a module that exposes a port | Serves the exposed ports and holds their domains and certificates |
| The execution environment's security group listed on that preview ingress | Lets the ingress's router reach the sandbox hosts |

## Usage

In a project's `ravion.yaml`, in the same environment as the preview ingress it references:

```yaml
environments:
  - givenId: staging
    name: Staging
    moduleInstances:
      - givenId: previews
        name: Previews
        type: rvn-preview-ingress
        version: 0.1.0
        input:
          network:
            moduleGivenIdRef: vpc # Must be type rvn-aws-network
          sandbox_host_security_group_ids:
            - sg-0123456789abcdef0

      - givenId: api
        name: API
        type: rvn-preview
        version: 0.1.0
        input:
          ingress:
            moduleGivenIdRef: previews # Must be type rvn-preview-ingress
          source_repo: my-org/my-repo
          source_base_path: "."
          pull_request_previews_enabled: true
          steps:
            - command: docker compose up -d --build --wait
          ports:
            - name: web
              port: 3000
              health_check_path: /healthz
          environment_variables:
            - name: DATABASE_HOST
              value: << modules.db.output.endpoint >>
          sandbox_execution_environment_id: ee_0123456789
```

A module with no `ports` runs its steps, serves no address, and needs no `ingress`:

```yaml
      - givenId: worker
        name: Worker
        type: rvn-preview
        version: 0.1.0
        input:
          source_repo: my-org/my-repo
          steps:
            - command: make run-worker
          sandbox_execution_environment_id: ee_0123456789
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ingress | The `rvn-preview-ingress` module instance that serves the exposed ports. Required by a module with `ports` | module reference | unset | with `ports` |
| source_repo | Repository whose branches run as previews | repository URL | n/a | yes |
| source_base_path | Repository-relative directory the steps run in | `string` | `.` | no |
| pull_request_previews_enabled | Deploy a preview for every pull request of the repository and remove it when the pull request is closed | `boolean` | `false` | no |
| steps | Shell commands run in order on every deploy and every resume, as a list of `{command}` | `list(object)` | n/a | yes |
| ports | HTTP ports served through the preview ingress. The first is the primary address. See [Ports](#ports) | `list(object)` | `[]` | no |
| environment_variables | Plain environment variables set for every step, as a list of `{name, value}`. A value can reference another module's output | `list(object)` | `[]` | no |
| sandbox_execution_environment_id | Execution environment whose sandbox pool runs the previews | `string` | n/a | yes |
| sandbox_cpu | vCPUs of each sandbox | `number` | `2` | yes |
| sandbox_memory | Memory of each sandbox, in GiB | `number` | `4` | yes |
| sandbox_disk | Disk of each sandbox, in GiB | `number` | `20` | no |
| idle_timeout_seconds | Seconds without a running command or an open connection before a preview is paused. `0` keeps it running; other values start at 60. Unset uses 900, or 14400 for a pull request's preview | `number` | unset | no |
| retention_seconds | Seconds a paused preview is kept before it expires. Unset uses 86400, or 604800 for a pull request's preview | `number` | unset | no |

The `ingress` reference also fills `ingress_wildcard_domain_name` from the preview ingress's `wildcard_domain_name` output. The form shows it after the Default Ravion domain of each port.

### Ports

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the port, unique within the module: 1-60 lowercase letters, numbers, or hyphens | `string` | `web` | yes |
| port | Port the app listens on inside the sandbox | `number` | n/a | yes |
| health_check_path | Absolute HTTP path requested to tell whether the port is ready | `string` | `/` | yes |
| ravion_domain_name | Name of the port's address under the preview ingress's wildcard domain: one DNS label. The address is `<branch>-<name>.<ingress domain>`. Used only when `domains` is empty. Unset uses the module ID for the first port, and the module ID followed by the port's `name` for the others | `string` | unset | no |
| domains | At most one custom domain of the preview ingress, `*.<domain>`, used by no other port of the module. The address is `<branch>.<domain>`, and it replaces the default Ravion domain | `list(string)` | `[]` | no |

## The preview block

| Preview field | From |
| --- | --- |
| `source.repo`, `source.base_path` | `source_repo`, `source_base_path` |
| `steps` | The `command` of each entry of `steps` |
| `expose` | Each entry of `ports` |
| `variables` | `environment_variables` |
| `sandbox.executionEnvironmentId` | `sandbox_execution_environment_id` |
| `sandbox.cpu`, `sandbox.memoryMib`, `sandbox.diskGib` | `sandbox_cpu`, `sandbox_memory` times 1024, `sandbox_disk` |
| `ingress` | `ingress` |
| `idle`, `retention` | `idle_timeout_seconds`, `retention_seconds` |
| `pull_requests` | `pull_request_previews_enabled` |

## Variables Ravion sets

Every step also receives these variables. Names that start with `RAVION_` are reserved.

| Variable | Value |
| --- | --- |
| `RAVION_PREVIEW_URL` | Address of the first exposed port |
| `RAVION_PREVIEW_URL_<NAME>` | Address of each exposed port, named in upper case with hyphens as underscores |
| `RAVION_PREVIEW_BRANCH` | Branch of the preview |
| `RAVION_PREVIEW_COMMIT` | Commit the preview runs |
| `RAVION_PREVIEW_PULL_REQUEST` | Pull request number, set for a pull request's preview |
| `RAVION_PREVIEW_ENV_NAMES` | Names of all variables set for the step, separated by spaces |

## Validating the definition

```bash
make modules-tools-build
node tools/ravion-modules/dist/src/cli.js compile compute/preview/rvn-preview-definition.yml
```

Publishing validates the `preview` block against Ravion's module schema.
