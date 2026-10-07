import assert from "node:assert/strict";
import { resolve } from "node:path";
import { it } from "node:test";
import { compileDefinitionFile } from "../src/compiler.js";

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function record(value: unknown): Record<string, unknown> {
  assert.ok(isRecord(value));
  return value;
}

const names = [
  "primary_cpu_usage", "primary_memory_usage", "primary_iops", "primary_queries", "primary_rows_read", "primary_rows_written",
  "replication_lag", "vreplication_lag", "pod_cpu_usage", "pod_memory_usage", "pod_queries", "pod_rows_read", "pod_iops", "pod_ooms", "shard_storage_usage", "shard_storage_available",
  "avg_parallel_workers", "avg_shard_queries", "block_cache_hit_ratio", "blocks_dirtied", "blocks_hit", "blocks_read", "blocks_written", "connections", "cpu_duration_millis", "egress_bytes", "egress_bytes_per_query", "ingress_bytes", "ingress_bytes_per_query", "io_duration_millis", "latency_max", "latency_p50", "latency_p95", "latency_p99", "latency_p999", "max_egress_bytes", "max_ingress_bytes", "max_shard_queries",
  "planetscale_edge_bytes_received", "planetscale_edge_bytes_received_rate", "planetscale_edge_bytes_sent", "planetscale_edge_bytes_sent_rate",
  "queries", "query_errors", "rows_affected_per_query", "rows_read", "rows_read_per_query", "rows_read_per_returned", "rows_returned", "rows_returned_per_query", "rows_written", "storage_per_table", "total_duration_millis", "traffic_control_throttled", "traffic_control_warnings", "violations", "vtgate_cpu_avg_by_az", "vtgate_cpu_by_az", "vtgate_latency_p50", "vtgate_latency_p95", "vtgate_memory_avg_by_az", "vtgate_memory_by_az", "vtgate_requests",
];

it("exposes the complete Vitess time-series catalog through the saved integration", async () => {
  const path = resolve(process.cwd(), "../../database/planetscale_vitess/rvn-planetscale-vitess-definition.yml");
  const compiled = await compileDefinitionFile(path);
  const metrics = record(compiled.module.ui).metrics;
  assert.ok(Array.isArray(metrics));
  assert.deepEqual(metrics.map((entry: unknown) => record(entry).id).sort(), [...names].sort());
  assert.equal(new Set(names).size, 63);
  for (const entry of metrics) {
    const metric = record(entry);
    assert.equal(metric.type, "line");
    const source = record(metric.source);
    assert.equal(source.type, "planetscale");
    assert.equal(source.integration_id, "<< module.input.planetscale >>");
    assert.equal(source.database, "<< stack.output.database >>");
    assert.equal(source.branch, "<< stack.output.branch >>");
    assert.equal(source.name, metric.id);
    assert.equal("aws_account_id" in source, false);
    assert.equal("keyspace" in source, false, "branch-wide metrics work before default-keyspace adoption");
  }
});
