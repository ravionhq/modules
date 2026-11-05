import assert from "node:assert/strict"
import {spawnSync} from "node:child_process"
import {mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync} from "node:fs"
import {tmpdir} from "node:os"
import {join} from "node:path"
import {test} from "node:test"

const source = readFileSync(new URL("../../tools/install-tflint-aws.sh", import.meta.url), "utf8")
const config = readFileSync(new URL("../../.tflint.hcl", import.meta.url), "utf8")

function fixture(t, configuration = config) {
  const root = mkdtempSync(join(tmpdir(), "tflint-installer-"))
  t.after(() => rmSync(root, {recursive: true, force: true}))
  mkdirSync(join(root, "tools"))
  mkdirSync(join(root, "bin"))
  writeFileSync(join(root, ".tflint.hcl"), configuration)
  writeFileSync(join(root, "tools/install-tflint-aws.sh"), source)
  function command(name, content) {
    writeFileSync(join(root, "bin", name), `#!/bin/sh\n${content}\n`, {mode: 0o755})
  }
  command("uname", 'if [ "$1" = "-s" ]; then echo Linux; else echo x86_64; fi')
  command("curl", 'echo "unexpected network request" >&2; exit 91')
  const env = {...process.env, HOME: root, PATH: `${join(root, "bin")}:${process.env.PATH}`}
  delete env.TFLINT_PLUGIN_DIR
  return {root, env, command, run: () => spawnSync("bash", [join(root, "tools/install-tflint-aws.sh")], {env, encoding: "utf8"})}
}

test("config drift fails before requesting a release", (t) => {
  const f = fixture(t, config.replace('version = "0.38.0"', 'version = "0.39.0"'))
  const result = f.run()
  assert.equal(result.status, 1)
  assert.match(result.stderr, /checksums to match/)
  assert.doesNotMatch(result.stderr, /unexpected network/)
})

test("verified cached plugin needs no network", (t) => {
  const f = fixture(t)
  const dir = join(f.root, ".tflint.d/plugins/github.com/terraform-linters/tflint-ruleset-aws/0.38.0")
  mkdirSync(dir, {recursive: true})
  writeFileSync(join(dir, "tflint-ruleset-aws"), "cached fixture", {mode: 0o755})
  f.command("sha256sum", "echo bdea6c87e9962b80eb674d7d8e7bfab89ea72295664fa4fb83b371d4799beb2d")
  const result = f.run()
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /cached and verified/)
})

test("download failure propagates", (t) => {
  const result = fixture(t).run()
  assert.equal(result.status, 91)
})

test("untrusted archive is rejected before extraction", (t) => {
  const f = fixture(t)
  f.command("curl", "exit 0")
  f.command("sha256sum", "echo invalid-checksum")
  f.command("unzip", 'echo "unexpected extraction" >&2; exit 92')
  const result = f.run()
  assert.equal(result.status, 1)
  assert.match(result.stderr, /archive checksum mismatch/)
  assert.doesNotMatch(result.stderr, /unexpected extraction/)
})

test("clean installation writes an executable plugin to the versioned directory", (t) => {
  const f = fixture(t)
  f.command("curl", "exit 0")
  f.command("sha256sum", `case "$1" in
    */plugin.zip) echo e81212eef130a2bacd537e9159a65de6a6a1ab8b5cdbd1a5e919b60bee46b120 ;;
    *) echo bdea6c87e9962b80eb674d7d8e7bfab89ea72295664fa4fb83b371d4799beb2d ;;
  esac`)
  f.command("unzip", "printf 'verified binary fixture'")
  const result = f.run()
  assert.equal(result.status, 0, result.stderr)
  const destination = join(f.root, ".tflint.d/plugins/github.com/terraform-linters/tflint-ruleset-aws/0.38.0/tflint-ruleset-aws")
  assert.equal(readFileSync(destination, "utf8"), "verified binary fixture")
  assert.equal(statSync(destination).mode & 0o777, 0o755)
})

test("a bad replacement binary leaves the existing plugin unchanged", (t) => {
  const f = fixture(t)
  const dir = join(f.root, ".tflint.d/plugins/github.com/terraform-linters/tflint-ruleset-aws/0.38.0")
  mkdirSync(dir, {recursive: true})
  const destination = join(dir, "tflint-ruleset-aws")
  writeFileSync(destination, "existing plugin", {mode: 0o755})
  f.command("curl", "exit 0")
  f.command("sha256sum", `case "$1" in
    */plugin.zip) echo e81212eef130a2bacd537e9159a65de6a6a1ab8b5cdbd1a5e919b60bee46b120 ;;
    *) echo invalid-binary-checksum ;;
  esac`)
  f.command("unzip", "printf 'untrusted replacement'")
  const result = f.run()
  assert.equal(result.status, 1)
  assert.match(result.stderr, /binary checksum mismatch/)
  assert.equal(readFileSync(destination, "utf8"), "existing plugin")
})
