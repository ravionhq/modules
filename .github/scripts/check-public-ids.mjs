// Fails a pull request whose title, description or added lines carry an ID that looks like it was
// copied from a real Ravion or AWS resource. This repository is public, so example IDs must be
// placeholders.
//
// What counts as real-looking:
// - A Ravion resource ID: a known prefix, an underscore and 24-30 letters and digits. Ravion IDs are
//   KSUIDs, which start with their creation time; one whose first character is "0" predates Ravion,
//   so `proj_0...` style placeholders always pass.
// - An AWS resource ID (vpc-, subnet-, rtb-, nat-, sg-, i-) with a 17-character hex suffix.
// - Any line of the PUBLIC_REPO_BLOCKED_STRINGS secret. It holds values that must not appear here
//   at all and so cannot be written in this public file.
//
// Placeholders that do not follow the "0" rule go in .github/public-id-allowlist.txt.
//
// The merge queue's status block in the description is skipped: the merge queue writes it, not
// the author.

import {readFileSync} from "node:fs"

const RAVION_ID = /(?<![0-9A-Za-z])(?:proj|env|minst|ee|stk|prun|sexec|pipe|awsact|svcact|org|mq|mdef|mdep)_[0-9A-Za-z]{24,30}(?![0-9A-Za-z])/g
const AWS_ID = /(?<![0-9A-Za-z-])(?:vpc|subnet|rtb|nat|sg|i)-0[0-9a-f]{16}(?![0-9A-Za-z])/g
const MERGE_QUEUE_BLOCK = /<!-- ravion-merge-queue:start -->[\s\S]*?<!-- ravion-merge-queue:end -->/g

export function parseList(text) {
  return (text ?? "")
    .split(/\r?\n/)
    .map((line) => line.replace(/#.*/, "").trim())
    .filter((line) => line.length > 0)
}

// Shows enough of a value to find it without republishing it in a public log.
export function redact(value) {
  const separator = value.search(/[_-]/)
  const head = separator === -1 ? 0 : separator + 1
  return `${value.slice(0, head + 2)}…`
}

function isPlaceholder(value, allowlist) {
  if (allowlist.has(value)) {
    return true
  }
  const underscore = value.indexOf("_")
  return underscore !== -1 && value[underscore + 1] === "0"
}

// Returns {line, kind, value} for each real-looking value in `text`; `line` is 1-based.
export function scanText(text, {allowlist = new Set(), blocked = []} = {}) {
  const findings = []
  text.split("\n").forEach((content, index) => {
    for (const match of content.matchAll(RAVION_ID)) {
      if (!isPlaceholder(match[0], allowlist)) {
        findings.push({line: index + 1, kind: "Ravion resource ID", value: match[0]})
      }
    }
    for (const match of content.matchAll(AWS_ID)) {
      if (!allowlist.has(match[0])) {
        findings.push({line: index + 1, kind: "AWS resource ID", value: match[0]})
      }
    }
    for (const value of blocked) {
      if (content.includes(value)) {
        findings.push({line: index + 1, kind: "blocked value", value})
      }
    }
  })
  return findings
}

export function scanDescription(body, options) {
  // Blank the block but keep its line breaks so line numbers still match the description.
  return scanText((body ?? "").replace(MERGE_QUEUE_BLOCK, (block) => block.replace(/[^\n]/g, "")), options)
}

// Returns the added lines of a unified diff patch with their line numbers in the new file.
export function addedLines(patch) {
  const lines = []
  let next = 0
  for (const content of (patch ?? "").split("\n")) {
    const hunk = content.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
    if (hunk) {
      next = Number(hunk[1])
    } else if (content.startsWith("+")) {
      lines.push({line: next, content: content.slice(1)})
      next += 1
    } else if (!content.startsWith("-") && !content.startsWith("\\")) {
      next += 1
    }
  }
  return lines
}

export function scanPatch(patch, options) {
  return addedLines(patch).flatMap(({line, content}) =>
    scanText(content, options).map((finding) => ({...finding, line})),
  )
}

export function formatFinding(where, {line, kind, value}) {
  const shown = kind === "blocked value" ? "a value from PUBLIC_REPO_BLOCKED_STRINGS" : redact(value)
  return `${where}${line ? `:${line}` : ""}: ${kind} ${shown}`
}

// Entry point for actions/github-script.
export async function run({github, context, core}) {
  const blocked = parseList(process.env.PUBLIC_REPO_BLOCKED_STRINGS)
  blocked.forEach((value) => core.setSecret(value))
  if (blocked.length === 0) {
    core.warning("PUBLIC_REPO_BLOCKED_STRINGS is not set; only ID shapes are checked.")
  }
  const allowlist = new Set(parseList(readFileSync(process.env.ALLOWLIST_PATH, "utf8")))
  const options = {allowlist, blocked}

  // Read the pull request again: a re-run reuses the original event, and the description may have
  // been fixed since.
  const {data: pr} = await github.rest.pulls.get({...context.repo, pull_number: context.payload.pull_request.number})
  const failures = [
    ...scanText(pr.title ?? "", options).map((finding) => formatFinding("title", {...finding, line: 0})),
    ...scanDescription(pr.body, options).map((finding) => formatFinding("description", finding)),
  ]

  const files = await github.paginate(github.rest.pulls.listFiles, {
    ...context.repo,
    pull_number: pr.number,
    per_page: 100,
  })
  for (const file of files) {
    if (file.status === "removed") {
      continue
    }
    if (file.patch !== undefined) {
      failures.push(...scanPatch(file.patch, options).map((finding) => formatFinding(file.filename, finding)))
      continue
    }
    // GitHub leaves out the patch of a binary or very large file. Read the blob as data; it is never
    // executed.
    const {data: blob} = await github.rest.git.getBlob({...context.repo, file_sha: file.sha})
    const content = Buffer.from(blob.content, "base64").toString("utf8")
    if (content.includes("\u0000")) {
      continue
    }
    failures.push(...scanText(content, options).map((finding) => formatFinding(file.filename, finding)))
  }

  if (failures.length > 0) {
    core.setFailed(
      [
        "This repository is public. These look like IDs of real resources:",
        ...failures.map((failure) => `  ${failure}`),
        "",
        "Describe the resource in words, or use a placeholder: a Ravion ID whose first character after the",
        "prefix is 0 (for example proj_0Pc2jb3JZ89x2IqBmXKeu8n5RIO), or a value listed in",
        ".github/public-id-allowlist.txt.",
      ].join("\n"),
    )
    return
  }
  core.info("No real-looking IDs found.")
}
