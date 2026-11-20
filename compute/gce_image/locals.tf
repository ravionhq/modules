locals {
  ################################################################################
  # Labels
  ################################################################################

  # GCP label keys and values allow only lowercase letters, numbers, hyphens,
  # and underscores, up to 63 characters.
  default_labels = {
    managed-by = "terraform"
    module     = "compute-gce-image"
  }
  labels = {
    for key, value in merge(local.default_labels, var.labels) :
    substr(replace(lower(key), "/[^a-z0-9_-]/", "-"), 0, 63) => substr(replace(lower(value), "/[^a-z0-9_-]/", "-"), 0, 63)
  }

  ################################################################################
  # Names
  ################################################################################

  zone = coalesce(var.zone, try(sort(data.google_compute_zones.available.names)[0], null))

  # Service account ids are 6-30 characters. A long name keeps its start and a
  # hash of the whole, so two long names that share a start stay apart.
  builder_account_id = length(var.name) <= 22 ? "${var.name}-builder" : "${substr(var.name, 0, 13)}-${substr(sha256(var.name), 0, 7)}-bld"

  # Bucket names are global across every project, so the project's hash keeps
  # the same module name in two projects from colliding.
  component_bucket_name = "${var.name}-components-${substr(sha256(var.project_id), 0, 8)}"

  network_project_id = coalesce(var.network_project_id, var.project_id)

  ################################################################################
  # Components
  ################################################################################

  # Each component is written as one bash script that runs one phase:
  #
  #   <component>.sh build|validate|test
  #
  # Every step is embedded base64-encoded, so no command can break the
  # script's quoting, and runs as its own `bash -euo pipefail` with stdin
  # closed: a command that reads stdin cannot swallow the steps after it. The
  # script prints "gce-image: <phase> step <name> started" before each step
  # and "gce-image: <phase> step <name> failed with exit <code>" when one
  # fails, then exits with that code. A parameter the environment leaves unset
  # takes its default; one with no default stays unset.
  component_phases = {
    for c in var.components : c.name => {
      build    = c.build_steps
      validate = c.validate_steps
      test     = c.test_steps
    }
  }

  component_scripts = {
    for c in var.components : c.name => join("\n", flatten([
      "#!/bin/bash",
      "# Component ${c.name}, written by the gce_image module.",
      try(trimspace(c.description), "") == "" ? [] : ["# ${replace(trimspace(c.description), "\n", " ")}"],
      "# Usage: ${c.name}.sh build|validate|test",
      "set -uo pipefail",
      "phase=\"$${1:-}\"",
      [
        for p in c.parameter_definitions : p.default == null ? "export ${p.name}" :
        "if [ -z \"$${${p.name}+set}\" ]; then ${p.name}=\"$(printf '%s' '${base64encode(p.default)}' | base64 -d)\"; fi; export ${p.name}"
      ],
      "run_step() {",
      "  local name=\"$1\" timeout=\"$2\" body=\"$3\" file rc",
      "  file=\"$(mktemp)\"",
      "  printf '%s' \"$body\" | base64 -d > \"$file\"",
      "  echo \"gce-image: $phase step $name started\"",
      "  if [ \"$timeout\" -gt 0 ]; then",
      "    timeout --kill-after=30 \"$timeout\" bash -euo pipefail \"$file\" < /dev/null",
      "  else",
      "    bash -euo pipefail \"$file\" < /dev/null",
      "  fi",
      "  rc=$?",
      "  rm -f \"$file\"",
      "  if [ \"$rc\" -ne 0 ]; then",
      "    echo \"gce-image: $phase step $name failed with exit $rc\"",
      "    exit \"$rc\"",
      "  fi",
      "}",
      "case \"$phase\" in",
      [
        for phase in ["build", "validate", "test"] : concat(
          ["  ${phase})"],
          length(local.component_phases[c.name][phase]) == 0 ? ["    :"] : [
            for step in local.component_phases[c.name][phase] :
            "    run_step '${step.name}' ${step.timeout_seconds == null ? 0 : floor(step.timeout_seconds)} '${base64encode(join("\n", step.commands))}'"
          ],
          ["    ;;"],
        )
      ],
      "  *)",
      "    echo \"usage: $0 build|validate|test\" >&2",
      "    exit 2",
      "    ;;",
      "esac",
      "",
    ]))
  }

  # A component's object is named by a hash of its script: a changed component
  # is a new object beside the old one, never an overwrite.
  component_objects = {
    for c in var.components : c.name => {
      sha256 = sha256(local.component_scripts[c.name])
      object = "components/${c.name}-${substr(sha256(local.component_scripts[c.name]), 0, 16)}.sh"
    }
  }
}
