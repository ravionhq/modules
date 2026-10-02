// Run after tofu init -backend=false and npm ci in tools/ravion-modules:
// node --test compute/eks/addons/tests/test_s3_observability_charts.mjs
// Uses mock-provider plans and Helm template only; never contacts a cluster.
import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse, parseAllDocuments } from '../../../../tools/ravion-modules/node_modules/yaml/dist/index.js';

const module = fileURLToPath(new URL('../', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'ravion-observability-charts-'));
after(() => rmSync(directory, { recursive: true, force: true }));
const env = {
  ...process.env,
  HELM_REPOSITORY_CONFIG: join(directory, 'repositories.yaml'),
  HELM_REPOSITORY_CACHE: join(directory, 'cache'),
};
const events = execFileSync('tofu', [
  'test', '-filter=tests/s3_observability.tftest.hcl', '-json', '-verbose',
], { cwd: module, encoding: 'utf8', maxBuffer: 50 * 1024 * 1024, timeout: 180000 })
  .trim().split('\n').map(line => JSON.parse(line));
const plan = events.find(event => event.type === 'test_plan' && event['@testrun'] === 'render_contract').test_plan;
const releases = Object.fromEntries(plan.planned_values.root_module.resources
  .filter(resource => resource.type === 'helm_release')
  .map(resource => [resource.name, resource.values]));

function render(resource) {
  const values = releases[resource];
  const args = ['template', values.name, values.chart, '--namespace', values.namespace, '--kube-version', '1.36.0'];
  if (values.repository) args.push('--repo', values.repository, '--version', values.version);
  values.values.forEach((value, index) => {
    const path = join(directory, `${resource}-${index}.yaml`);
    writeFileSync(path, value);
    args.push('--values', path);
  });
  return parseAllDocuments(execFileSync('helm', args, {
    cwd: module, env, encoding: 'utf8', timeout: 120000, maxBuffer: 10 * 1024 * 1024,
  })).map(document => document.toJSON()).filter(Boolean);
}

const prometheus = render('prometheus');
const thanos = render('thanos');
const tempo = render('tempo');
const collector = render('otlp_collector');

const object = (documents, kind, name) => documents.find(document => document.kind === kind && (!name || document.metadata.name === name));

test('generated S3 buckets block public access and encrypt data; only Tempo\'s expires, after its retention', () => {
  for (const name of ['thanos_bucket', 'tempo_bucket']) {
    const bucket = plan.planned_values.root_module.child_modules.find(child => child.address === `module.${name}[0]`);
    assert.ok(bucket);
    const values = type => bucket.resources.find(resource => resource.type === type).values;
    const publicAccess = values('aws_s3_bucket_public_access_block');
    for (const key of ['block_public_acls', 'block_public_policy', 'ignore_public_acls', 'restrict_public_buckets']) {
      assert.equal(publicAccess[key], true);
    }
    const encryption = values('aws_s3_bucket_server_side_encryption_configuration');
    assert.equal(encryption.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm, 'AES256');
    assert.ok(values('aws_s3_bucket_policy'));
    for (const rule of values('aws_s3_bucket_lifecycle_configuration').rule) {
      if (name === 'thanos_bucket') {
        assert.ok(!rule.expiration || rule.expiration.length === 0);
      } else if (rule.expiration && rule.expiration.length > 0) {
        assert.ok(rule.expiration[0].days > 30);
      }
    }
  }
});

test('sidecar shares the real Prometheus PVC and matches its gRPC Service selector', () => {
  const deployment = object(prometheus, 'Deployment');
  const pod = deployment.spec.template.spec;
  const sidecar = pod.containers.find(container => container.name === 'thanos');
  const server = pod.containers.find(container => container.name === 'prometheus-server');
  assert.ok(server.args.includes('--storage.tsdb.max-block-duration=2h'));
  assert.ok(server.args.includes('--storage.tsdb.min-block-duration=2h'));
  assert.ok(server.args.includes('--web.enable-remote-write-receiver'));
  const mount = sidecar.volumeMounts.find(volume => volume.mountPath === '/data');
  assert.equal(mount.name, server.volumeMounts.find(volume => volume.mountPath === '/data').name);
  assert.ok(pod.volumes.find(volume => volume.name === mount.name).persistentVolumeClaim);
  assert.equal(pod.serviceAccountName, 'ravion-prometheus');
  const service = object(thanos, 'Service', 'ravion-thanos-sidecar');
  for (const [label, value] of Object.entries(service.spec.selector)) {
    assert.equal(deployment.spec.template.metadata.labels[label], value);
  }
  assert.ok(sidecar.ports.some(port => port.name === service.spec.ports[0].targetPort));
  const config = parse(object(prometheus, 'ConfigMap').data['prometheus.yml']);
  assert.deepEqual(config.scrape_configs, []);
  assert.equal(config.global.external_labels.cluster, 'test-cluster');
});

test('Query reads live and S3 stores, while only one Compactor manages retention', () => {
  const query = object(thanos, 'Deployment', 'ravion-thanos-query');
  const args = query.spec.template.spec.containers[0].args;
  assert.ok(args.includes('--endpoint=dns+ravion-thanos-sidecar.ravion-operator.svc.cluster.local:10901'));
  assert.ok(args.includes('--endpoint=dns+ravion-thanos-store.ravion-operator.svc.cluster.local:10901'));
  const service = object(thanos, 'Service', 'ravion-thanos-query');
  assert.equal(service.spec.ports[0].port, 9090);
  assert.equal(service.spec.ports[0].targetPort, 'http');
  const compactor = object(thanos, 'StatefulSet');
  assert.equal(compactor.spec.replicas, 1);
  assert.equal(compactor.spec.volumeClaimTemplates[0].spec.storageClassName, 'gp3');
  for (const resolution of ['raw', '5m', '1h']) {
    assert.ok(compactor.spec.template.spec.containers[0].args.includes(`--retention.resolution-${resolution}=365d`));
  }
  const config = parse(object(thanos, 'ConfigMap').data['bucket.yaml']);
  assert.equal(config.config.aws_sdk_auth, true);
  assert.equal(config.config.bucket, 'ravion-metrics-test-cluster-123456789012');
  assert.ok(!('access_key' in config.config));
});

test('Tempo uses S3, a persistent WAL, 30-day retention and receives OTLP', () => {
  const stateful = object(tempo, 'StatefulSet');
  assert.equal(stateful.spec.template.spec.serviceAccountName, 'ravion-tempo');
  assert.equal(stateful.spec.volumeClaimTemplates[0].spec.storageClassName, 'gp3');
  const config = parse(object(tempo, 'ConfigMap').data['tempo.yaml']);
  assert.equal(config.storage.trace.backend, 's3');
  assert.equal(config.storage.trace.s3.bucket, 'ravion-tempo-test-cluster-123456789012');
  assert.equal(config.storage.trace.wal.path, '/var/tempo/wal');
  assert.equal(config.backend_scheduler.provider.compaction.compaction.block_retention, '720h');
  assert.equal(config.distributor.receivers.otlp.protocols.grpc.endpoint, '0.0.0.0:4317');
  assert.ok(!('access_key' in config.storage.trace.s3));
});

test('the actual collector config sends OTLP traces to Tempo and workload metrics to Prometheus, with Kubernetes enrichment', () => {
  const config = parse(object(collector, 'ConfigMap').data.relay);
  assert.deepEqual(Object.keys(config.service.pipelines).sort(), ['metrics', 'traces']);
  assert.deepEqual(config.service.pipelines.traces.exporters, ['otlp_grpc/tempo']);
  assert.deepEqual(config.service.pipelines.metrics.exporters, ['prometheusremotewrite/in_cluster']);
  assert.deepEqual(config.service.pipelines.traces.receivers, ['otlp']);
  assert.ok(config.processors.k8s_attributes);
  for (const pipeline of ['traces', 'metrics']) {
    assert.ok(config.service.pipelines[pipeline].processors.includes('k8s_attributes'));
  }
  assert.equal(config.exporters['otlp_grpc/tempo'].endpoint, 'ravion-tempo.ravion-operator.svc.cluster.local:4317');
  assert.equal(config.receivers.otlp.protocols.http.endpoint, '${env:MY_POD_IP}:4318');
  assert.ok(object(collector, 'ClusterRole'));
});

// Opt-in runtime config validation; pulls the exact configured images.
const validateImages = process.env.RAVION_OBSERVABILITY_VALIDATE_IMAGES === '1';
test('the configured collector image accepts the rendered trace config', { skip: !validateImages }, () => {
  const path = join(directory, 'collector-runtime.yaml');
  writeFileSync(path, object(collector, 'ConfigMap').data.relay);
  const values = parse(releases.otlp_collector.values[0]);
  execFileSync('docker', ['run', '--rm', '--network', 'none', '-e', 'MY_POD_IP=127.0.0.1',
    '-v', `${path}:/etc/otel/config.yaml:ro`, `${values.image.repository}:${values.image.tag}`,
    'validate', '--config=/etc/otel/config.yaml'], { encoding: 'utf8', timeout: 180000 });
});

test('the configured Tempo image accepts the rendered trace config', { skip: !validateImages }, () => {
  const path = join(directory, 'tempo-runtime.yaml');
  writeFileSync(path, object(tempo, 'ConfigMap').data['tempo.yaml']);
  const image = object(tempo, 'StatefulSet').spec.template.spec.containers[0].image;
  execFileSync('docker', ['run', '--rm', '--network', 'none',
    '-v', `${path}:/etc/tempo.yaml:ro`, image,
    '-config.file=/etc/tempo.yaml', '-config.verify=true'], { encoding: 'utf8', timeout: 180000 });
});

test('all rendered endpoints remain ClusterIP, with no public ingress', () => {
  for (const documents of [prometheus, thanos, tempo, collector]) {
    assert.ok(!documents.some(document => document.kind === 'Ingress'));
    for (const service of documents.filter(document => document.kind === 'Service')) {
      assert.ok(!service.spec.type || service.spec.type === 'ClusterIP');
    }
  }
});
