import assert from "node:assert/strict"
import {test} from "node:test"

import {addedLines, formatFinding, parseList, redact, scanDescription, scanPatch, scanText} from "./check-public-ids.mjs"

const realShaped = `prun_3${"aB7".repeat(8)}xy`
const placeholder = "prun_0vFqdVwCbNCyIFHuEd7YGcH8F0q"
// Built at run time so this file passes the check it tests.
const id = (...parts) => parts.join("")
const listedRun = id("prun_3", "GnVYOJUpc68VxNmvJGPzZjKuJ")
const listedVpc = id("vpc-0", "f1e2d3c4b5a69788")
const routeTable = id("rtb-0", "aaaaaaaaaaaaaaab")
const instance = id("i-0", "123456789abcdef1")

test("a Ravion ID of the real shape is reported with its line", () => {
  assert.deepEqual(scanText(`intro\nrun ${realShaped} failed`), [
    {line: 2, kind: "Ravion resource ID", value: realShaped},
  ])
})

test("placeholders starting with 0 and allowlisted values pass", () => {
  const allowlist = new Set([listedRun, listedVpc])
  const text = `${placeholder} ${listedRun} ${listedVpc}`
  assert.deepEqual(scanText(text, {allowlist}), [])
})

test("AWS resource IDs are reported unless allowlisted", () => {
  const text = `route table ${routeTable} and instance ${instance}`
  assert.deepEqual(
    scanText(text).map((finding) => finding.value),
    [routeTable, instance],
  )
  assert.deepEqual(scanText(text, {allowlist: new Set([routeTable, instance])}), [])
})

test("words that only contain an ID-like suffix do not match", () => {
  const text = [
    "api-0123456789abcdef0 is a hostname fragment",
    "free_ABCDEFGHIJKLMNOPQRSTUVWXYZ is not an ee_ ID",
    "sg-0123456789abcdef0123 is too long",
    "environment_variables_are_not_ids_either_xx",
  ].join("\n")
  assert.deepEqual(scanText(text), [])
})

test("blocked values are reported without being echoed", () => {
  const findings = scanText("account 999988887777 here", {blocked: ["999988887777"]})
  assert.deepEqual(findings, [{line: 1, kind: "blocked value", value: "999988887777"}])
  assert.equal(formatFinding("README.md", findings[0]), "README.md:1: blocked value a value from PUBLIC_REPO_BLOCKED_STRINGS")
})

test("findings are redacted in output", () => {
  assert.equal(redact(realShaped), "prun_3a…")
  assert.equal(redact("vpc-0123456789abcdef0"), "vpc-01…")
})

test("the merge queue status block in a description is skipped", () => {
  const body = [
    "<!-- ravion-merge-queue:start -->",
    "- [x] In merge queue / [Queued](https://example.com/org/abc/merge-queues?queue=mq_0KphfwHjQ9gjpSwkHxdx9Zkql8V)",
    "<!-- ravion-merge-queue:end -->",
    "",
    `Run ${realShaped} failed.`,
  ].join("\n")
  assert.deepEqual(scanDescription(body), [{line: 5, kind: "Ravion resource ID", value: realShaped}])
})

test("only added lines of a patch are scanned, with new-file line numbers", () => {
  const patch = [
    "@@ -10,3 +10,4 @@ section",
    ` unchanged ${realShaped}`,
    `-removed ${realShaped}`,
    `+added ${realShaped}`,
    " context",
    "\\ No newline at end of file",
  ].join("\n")
  assert.deepEqual(addedLines(patch), [{line: 11, content: `added ${realShaped}`}])
  assert.deepEqual(scanPatch(patch), [{line: 11, kind: "Ravion resource ID", value: realShaped}])
})

test("list files ignore comments and blank lines", () => {
  assert.deepEqual(parseList("# examples\n\nproj_0Pc2jb3JZ89x2IqBmXKeu8n5RIO  # docs\n"), ["proj_0Pc2jb3JZ89x2IqBmXKeu8n5RIO"])
})
