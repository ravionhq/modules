# Temporal on EKS

Self-hosted [Temporal](https://temporal.io) on an existing EKS cluster, with its persistence and visibility stores on an Aurora PostgreSQL cluster.

The module installs two Helm releases into one namespace:

1. `<name>-resources`, a local chart ([`charts/temporal-resources`](charts/temporal-resources)) with everything around Temporal:
   - `ExternalSecret`s that copy the database password, and any other secret the module uses, from Secrets Manager, so no secret enters Helm values, release history or Terraform state
   - the RDS CA bundle, so the database connection verifies the server certificate
   - optionally: certificates from a CA of your choice, a JWKS key server, a PriorityClass, a dedicated Karpenter NodePool, network policies, an internal NLB and Tailscale devices for the frontend, a Tailscale Ingress for the Web UI, and an OTLP metrics forwarder
2. `<name>`, the official [temporalio/helm-charts](https://github.com/temporalio/helm-charts) `temporal` chart, pinned to a version: the frontend, history, matching and worker services (and an internal frontend with JWT authorization), the Web UI, the admin tools, a schema job that creates and migrates both databases, and a setup job that keeps the Temporal namespaces and their search attributes in place.

Every service gets resource requests and limits, a `GOMEMLIMIT` at 90% of its memory limit, zone and node spread, a PodDisruptionBudget, and graceful shutdown drains.

## Usage

```hcl
module "temporal" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks/temporal?ref=v1.0.0"

  cluster_name           = "my-eks-cluster"
  region                 = "us-east-1"
  ravion_runner_role_arn = "arn:aws:iam::123456789012:role/my-eks-cluster-ravion-runner"

  database_cluster_identifier  = "my-temporal-db"
  database_password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-temporal-db-AbCdEf"

  num_history_shards = 512
  temporal_namespaces = {
    default = {}
    orders = {
      retention_days    = 30
      search_attributes = { CustomerId = "Keyword", Amount = "Double" }
    }
  }

  history = { replicas = 3, memory_limit = "4Gi" }

  tls_enabled        = true
  jwt_auth_enabled   = true
  jwt_auth_audience  = "temporal"
  jwt_auth_jwks_urls = ["https://login.example.com/.well-known/jwks.json"]

  tailscale_web_enabled      = true
  tailscale_tailnet_domain   = "example-tailnet.ts.net"
  web_oidc_enabled           = true
  web_oidc_provider          = "google"
  web_oidc_client_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:temporal-oidc-AbCdEf"

  network_policy_frontend_client_namespaces = ["my-app"]
}
```

Clients in the cluster connect to the `frontend_address` output (`temporal-frontend.temporal.svc:7233` with the defaults).

## Prerequisites

- An EKS cluster with a storage driver and the External Secrets Operator with a `ClusterSecretStore` for Secrets Manager (`ravion-aws` from the EKS Add-ons module). The store must allow this namespace, and the operator must be able to read and decrypt every secret the module uses. A database password from an existing Kubernetes Secret (`database_password_source = "kubernetes_secret"`) needs no store, unless another feature reads Secrets Manager.
- An Aurora PostgreSQL cluster whose security group admits the EKS cluster's pods. The module checks the engine and refuses anything else.
- For `tls_enabled`, cert-manager. For `node_pool_creation_enabled`, Karpenter. For `frontend_nlb_enabled`, the AWS Load Balancer Controller. For the `tailscale_*` features, the Tailscale Kubernetes operator. For `metrics_service_monitor_enabled`, the Prometheus Operator CRDs.
- The AWS CLI on the machine running OpenTofu, for `aws eks get-token`.

## Features

### Namespaces and search attributes

`temporal_namespaces` maps each Temporal namespace to its `retention_days` (default 7) and `search_attributes` (name => `Keyword`, `KeywordList`, `Text`, `Int`, `Double`, `Bool` or `Datetime`). A post-install and post-upgrade job creates missing namespaces, applies retention, and registers missing attributes, so they exist before workers use the namespace. Attributes are only added, never removed. Postgres visibility allows each namespace **10 Keyword** attributes and **3 of each other type**; the module rejects more.

`temporal_namespaces` was a map of name to retention days before search attributes were added. Write `{ orders = { retention_days = 30 } }` where you wrote `{ orders = 30 }`.

### JWT authorization

With `jwt_auth_enabled` (requires `tls_enabled`), the frontend requires a JWT on every call, checked by Temporal's default claim mapper and authorizer. The token's permissions claim (`jwt_auth_permissions_claim_name`, default `permissions`) lists entries of the form `<namespace>:<read|write|worker|admin>`, plus `system:admin` for cluster-wide admin. `jwt_auth_audience` sets the required `aud`. Keys come from `jwt_auth_jwks_urls`, or from a JWKS document in Secrets Manager (`jwt_auth_jwks_source = "secrets_manager"`) that the module syncs and serves inside the namespace, for tokens you sign yourself.

Temporal's own components, the admin tools and the setup jobs reach an internal frontend with internode certificates instead of tokens, and are admin there, as Temporal intends.

### Roles for Web UI users

With authorization and Web UI sign-in both on, the UI forwards each user's ID token to the frontend, so the user's roles come from that token:

1. **From a token claim.** Have your identity provider add the permissions claim to its ID tokens (Okta, Auth0, Keycloak and Microsoft Entra ID can), and set `jwt_auth_audience` to the OIDC client ID. Google cannot add custom claims: with Google, leave `jwt_auth_enabled` off so sign-in only controls who reaches the UI, or use a custom claim mapper.
2. **From a custom claim mapper.** Bring a server image built with your own ClaimMapper (`server_image`), for example one that maps Google Workspace group membership to roles. Configure it with `frontend_extra_env`, `frontend_secret_env` (environment variables from Secrets Manager) and `server_secret_files` (Secrets Manager secrets mounted as files), and name it in `server.config.authorization.claimMapper` through `helm_values`.

`web_internal_frontend_enabled` connects the UI through the internal frontend as admin instead, for a UI whose access is already limited.

### Certificate authority

`tls_ca_source` picks what issues the frontend and internode certificates: `self_signed` (a CA created in the namespace, the default), `issuer` (an existing cert-manager Issuer or ClusterIssuer, `tls_issuer = { name, kind, group }`) or `secret` (an existing CA key pair Secret, `tls_ca_secret_name`). Clients always trust the `ca.crt` in the `tls_ca_secret_name` output's Secret, and `tls_issuer` names the issuer in use.

For **AWS Private CA**, install the [aws-privateca-issuer](https://github.com/cert-manager/aws-privateca-issuer) plugin, give its service account `acm-pca:DescribeCertificateAuthority`, `acm-pca:IssueCertificate` and `acm-pca:GetCertificate` on the CA through EKS Pod Identity, create an `AWSPCAClusterIssuer` for the CA, and set `tls_issuer = { name = "<issuer>", kind = "AWSPCAClusterIssuer", group = "awspca.cert-manager.io" }`.

### Frontend access from outside the cluster

- **Internal NLB** (`frontend_nlb_enabled`): the AWS Load Balancer Controller provisions an internal NLB for the frontend's port 7233, in `frontend_nlb_subnet_ids` or the subnets tagged `kubernetes.io/role/internal-elb`. Only `frontend_nlb_source_cidrs` can reach it. Client addresses are preserved, so those CIDRs, and the NLB's subnets for its health checks, are added to the frontend's network policy. `frontend_nlb_hostname` is its DNS name.
- **Tailscale** (`tailscale_frontend_enabled`): the Tailscale operator makes port 7233 a tailnet device named `tailscale_frontend_hostname`, tagged `tailscale_frontend_tags`. `tailscale_frontend_address` is its address.

Both pass TCP straight through, so TLS and token checks still happen at the frontend. With TLS, verify against `tls_server_name`, or add your own names with `tls_frontend_extra_dns_names`. The tailnet name is added automatically when `tailscale_tailnet_domain` is set.

For Tailscale, also: let the operator's tag own each device tag (`tagOwners`), grant your users access to the tag on `tcp:7233` (frontend) and `tcp:443` (Web UI), enable MagicDNS and HTTPS certificates for the Web UI, and set `tailscale_namespace` to the operator's proxy namespace so the network policies admit it.

### Web UI

The Web UI is a ClusterIP Service. Expose it through an Ingress (`web_ingress_enabled`, an internal ALB with the `alb` class) or on your tailnet over HTTPS (`tailscale_web_enabled`).

`web_oidc_enabled` adds OpenID Connect sign-in. `web_oidc_provider` presets the issuer and scopes for `google`; `okta` and `microsoft_entra` preset the scopes and need `web_oidc_issuer_url` (`https://<org>.okta.com`, `https://login.microsoftonline.com/<tenant ID>/v2.0`); `generic` needs both. The client ID and secret come from the JSON secret `web_oidc_client_secret_arn`. Register the callback URL, the `web_oidc_callback_url` output (`https://<Web UI host>/auth/sso/callback`), as an authorized redirect URI: in Google's OAuth client, Okta's sign-in redirect URIs, or a Web redirect URI of the Entra app registration.

## Notes

- **History shards are permanent.** `num_history_shards` cannot change after the first install without a new database.
- **Password rotation.** Temporal reads the password when a server starts. After the password changes, new database connections fail until the pods restart. Prefer a secret without automatic rotation, or restart the Temporal Deployments after each rotation. `server_secret_files` are not refreshed in running pods either.
- **Network policies** need a CNI that enforces them, such as the Amazon VPC CNI with network policy turned on. Without one they are inert.
- Archival, Elasticsearch visibility and multi-cluster replication are not configured. Use `helm_values` for them.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |
| helm | >= 3.1 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the existing EKS cluster to install Temporal onto. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| ravion_runner_role_arn | IAM role assumed by `aws eks get-token` to authenticate to the Kubernetes API (ravion_runner_role_arn output of the compute/eks stack). When null, the identity running Terraform is used directly and must already have cluster access. | `string` | `null` | no |
| name | Helm release name. Every Kubernetes object the release creates is prefixed with it, such as &lt;name&gt;-frontend. | `string` | `"temporal"` | no |
| namespace | Kubernetes namespace for Temporal. A namespace of its own keeps the network policies and the CA secret away from other workloads. | `string` | `"temporal"` | no |
| namespace_creation_enabled | Create the Kubernetes namespace. Turn off when it is managed elsewhere. | `bool` | `true` | no |
| chart_version | Version of the temporalio/helm-charts `temporal` chart. Chart 1.8.0 or newer is required for the TLS settings this module writes. | `string` | `"1.8.0"` | no |
| server_image | Temporal server image, as repository:tag. The admin tools image (schema and namespace jobs) uses admin_tools_image. | `string` | `"temporalio/server:1.32.2"` | no |
| admin_tools_image | Temporal admin tools image, as repository:tag. Keep it on the same Temporal version as server_image: it runs the schema migrations. | `string` | `"temporalio/admin-tools:1.32.2"` | no |
| web_image | Temporal Web UI image, as repository:tag. | `string` | `"temporalio/ui:2.56.1"` | no |
| log_level | Temporal server log level. | `string` | `"info"` | no |
| num_history_shards | Number of history shards. Fixed for the life of the cluster: it cannot be changed after the first install without a new database. Each shard costs a little memory and database load even when idle, and the shard count caps how far history can scale out. 512 suits most teams; choose 2048 or more for very high throughput. | `number` | `512` | no |
| database_cluster_identifier | Identifier of the Aurora PostgreSQL cluster Temporal uses. The cluster must accept connections from the EKS cluster's pods. | `string` | n/a | yes |
| database_username | Database user Temporal connects as. When null, the cluster's master username. | `string` | `null` | no |
| database_password_source | Where the database password comes from. `external_secrets` copies it from Secrets Manager with the External Secrets Operator; `kubernetes_secret` reads an existing Kubernetes Secret in the namespace. | `string` | `"external_secrets"` | no |
| database_password_secret_arn | ARN of the Secrets Manager secret holding the database credentials as JSON, such as the Aurora cluster's master user secret. Required when database_password_source is external_secrets. | `string` | `null` | no |
| database_password_secret_property | JSON key in the Secrets Manager secret that holds the password. | `string` | `"password"` | no |
| external_secrets_store_name | External Secrets ClusterSecretStore that reads Secrets Manager, for the database password, the JWKS key set, the Web UI's OIDC client and the frontend's secret environment and files. It must admit this namespace and be allowed to read each secret (and decrypt it, for a customer managed KMS key). | `string` | `"ravion-aws"` | no |
| database_password_refresh_interval | How often the External Secrets Operator re-reads the password. | `string` | `"1h"` | no |
| database_password_kubernetes_secret_name | Kubernetes Secret holding the password under the key `password`. With external_secrets it is created under this name; when null, &lt;name&gt;-db. | `string` | `null` | no |
| database_name | Database holding Temporal's persistence (workflow state and history). | `string` | `"temporal"` | no |
| visibility_database_name | Database holding Temporal's visibility records (workflow search and listing). | `string` | `"temporal_visibility"` | no |
| database_schema_management_enabled | Create both databases if missing and run Temporal's schema migrations on every deploy. Turn off only when a database administrator manages the schema. | `bool` | `true` | no |
| database_tls_enabled | Connect to the database over TLS and verify its certificate against the RDS CA bundle. | `bool` | `true` | no |
| database_max_connections | Maximum connections each Temporal server pod opens to the persistence database. Multiply by the number of server pods to size the database's max_connections. | `number` | `20` | no |
| visibility_database_max_connections | Maximum connections each Temporal server pod opens to the visibility database. | `number` | `10` | no |
| frontend | Frontend service: the gRPC API SDK clients, the Web UI and the CLI call. | `object` | `{}` | no |
| history | History service: owns the history shards and does most of the work. Scale it first, and give it memory: each pod caches the workflows of the shards it owns. | `object` | `{}` | no |
| matching | Matching service: hosts the task queues workers poll. | `object` | `{}` | no |
| worker | Internal worker service: runs Temporal's own system workflows, such as scheduled actions and batch operations. | `object` | `{}` | no |
| temporal_namespaces | Temporal namespaces, keyed by name. After every deploy a job creates each missing namespace, sets its retention (days closed workflows are kept), and registers its custom search attributes (name =&gt; type: Keyword, KeywordList, Text, Int, Double, Bool or Datetime). Attributes are only ever added: removing one here leaves it registered. Postgres visibility gives each namespace 10 Keyword slots and 3 of every other type. | `map(object)` | `{ default = {} }` | no |
| topology_spread | Spread each service's replicas across zones and nodes. `preferred` spreads when it can; `required` refuses to schedule a replica that would break the spread, which needs nodes in every zone (Karpenter adds them); `off` leaves placement to the scheduler. | `string` | `"preferred"` | no |
| pod_disruption_budgets_enabled | Let voluntary disruptions, such as node drains, take at most one replica of each service at a time. | `bool` | `true` | no |
| priority_class_creation_enabled | Create a PriorityClass ranking Temporal above ordinary workloads, so the scheduler preempts and the kubelet evicts other pods first. | `bool` | `false` | no |
| priority_class_name | PriorityClass for every Temporal pod. With priority_class_creation_enabled it is created under this name (when null, &lt;name&gt;-critical); otherwise it must already exist, or be null for none. | `string` | `null` | no |
| priority_class_value | Priority of the created PriorityClass. Keep it below the system-cluster-critical (2000000000) and system-node-critical classes. | `number` | `1000000` | no |
| node_pool_creation_enabled | Create a dedicated, tainted Karpenter NodePool and run Temporal on it alone, so other workloads cannot starve it and node consolidation moves its pods one node at a time. Requires Karpenter, such as from the EKS Add-ons module. | `bool` | `false` | no |
| node_pool | Settings for the dedicated NodePool. Spot capacity is allowed but not recommended: a reclaim moves history shards mid-flight. | `object` | `{}` | no |
| network_policy_enabled | Close the Temporal pods' internal ports to everything outside the release. Enforcement needs a CNI that implements NetworkPolicy, such as the Amazon VPC CNI with network policy turned on; without one the policies are inert. | `bool` | `true` | no |
| network_policy_frontend_client_namespaces | Namespaces whose pods may call the frontend (gRPC 7233, HTTP 7243). Empty allows every namespace in the cluster. | `list(string)` | `[]` | no |
| network_policy_web_client_namespaces | Namespaces whose pods may reach the Web UI, such as an ingress controller's. Empty allows every namespace in the cluster. | `list(string)` | `[]` | no |
| network_policy_web_client_cidrs | CIDR blocks that may reach the Web UI pods directly. The VPC CIDR is added automatically when the Web UI ingress is enabled. | `list(string)` | `[]` | no |
| network_policy_metrics_namespaces | Namespaces whose pods may scrape the servers' metrics port (9090). Empty allows every namespace in the cluster. | `list(string)` | `[]` | no |
| tls_enabled | Encrypt Temporal's traffic with certificates from a private CA that cert-manager creates in the namespace: mutual TLS between Temporal's services, and TLS on the frontend. Requires cert-manager, such as from the EKS Add-ons module. SDK clients must then connect with TLS and trust the CA in the frontend certificate secret's ca.crt. | `bool` | `false` | no |
| tls_frontend_client_auth_required | Require SDK clients to present a certificate from the private CA (mutual TLS) on the frontend. | `bool` | `false` | no |
| tls_frontend_extra_dns_names | More names for the frontend certificate, such as a DNS name you point at the NLB. The tailnet name is added automatically when tailscale_tailnet_domain is set. | `list(string)` | `[]` | no |
| tls_ca_source | Certificate authority that issues the frontend and internode certificates. `self_signed` creates a CA in the namespace; `issuer` uses an existing cert-manager Issuer or ClusterIssuer, such as an AWS Private CA issuer; `secret` uses an existing CA key pair Secret in the namespace. | `string` | `"self_signed"` | no |
| tls_issuer | Existing issuer for tls_ca_source = issuer. For AWS Private CA through aws-privateca-issuer, use kind AWSPCAClusterIssuer or AWSPCAIssuer and group awspca.cert-manager.io. | `object` | `null` | no |
| tls_ca_secret_name | For tls_ca_source = secret: a kubernetes.io/tls Secret in the namespace holding the CA certificate (tls.crt) and its private key (tls.key). | `string` | `null` | no |
| jwt_auth_enabled | Require a JWT on every frontend call, checked by Temporal's default claim mapper and authorizer. The token's permissions claim lists entries of the form &lt;namespace&gt;:&lt;read\|write\|worker\|admin&gt; (system:admin for cluster-wide admin). Requires tls_enabled: Temporal's own components then reach the cluster through an internal frontend with their internode certificates, as admin. | `bool` | `false` | no |
| jwt_auth_audience | Audience (aud) the frontend requires in tokens. When null, the audience is not checked. | `string` | `null` | no |
| jwt_auth_permissions_claim_name | Token claim holding the permissions list. | `string` | `"permissions"` | no |
| jwt_auth_jwks_source | Where the frontend reads the signing keys. `url` fetches one or more JWKS URLs, such as an identity provider's; `secrets_manager` syncs a JWKS document from Secrets Manager through External Secrets and serves it inside the namespace, for tokens you sign yourself. | `string` | `"url"` | no |
| jwt_auth_jwks_urls | JWKS URLs for jwt_auth_jwks_source = url. The frontend drops a whole refresh when any of them fails, so list only reliable ones. | `list(string)` | `[]` | no |
| jwt_auth_jwks_secret_arn | Secrets Manager secret holding the JWKS document ({"keys": [...]}) for jwt_auth_jwks_source = secrets_manager. | `string` | `null` | no |
| jwt_auth_jwks_secret_property | JSON key holding the JWKS document inside the secret. When null, the whole secret string is the document. | `string` | `null` | no |
| jwt_auth_jwks_refresh_interval | How often the frontend reloads the signing keys, and how often External Secrets re-reads them from Secrets Manager. | `string` | `"1m"` | no |
| jwt_auth_jwks_server_image | Image of the small web server that serves a JWKS document synced from Secrets Manager. It must serve /usr/share/nginx/html on port 8080 as a non-root user. | `string` | `"nginxinc/nginx-unprivileged:1.28.1-alpine"` | no |
| internal_frontend | Internal frontend, run when jwt_auth_enabled: Temporal's own workers, the admin tools and the setup jobs call it with internode certificates instead of tokens. | `object` | `{}` | no |
| web_internal_frontend_enabled | Connect the Web UI through the internal frontend with an internode certificate, so it acts as admin without a token. With jwt_auth_enabled the UI otherwise needs each user's token, from OIDC sign-in. Only for a Web UI that already restricts who reaches it. | `bool` | `false` | no |
| frontend_extra_env | Plain environment variables for the frontend pods, such as settings for a custom claim mapper in your own server_image. | `map(string)` | `{}` | no |
| frontend_secret_env | Environment variables for the frontend pods read from Secrets Manager, keyed by variable name. External Secrets syncs them into a Kubernetes Secret, so the values stay out of Helm values and Terraform state. Without property, the whole secret string is the value. | `map(object)` | `{}` | no |
| server_secret_files | Secrets Manager secrets mounted as read-only files into the Temporal server pods, keyed by absolute file path, such as a service account key a custom claim mapper reads. Without property, the whole secret string is the file. Files are not refreshed in running pods: restart them after a change. | `map(object)` | `{}` | no |
| frontend_nlb_enabled | Expose the frontend's gRPC port on an internal Network Load Balancer, for clients outside the cluster, such as in a peered VPC. TCP passes straight through, so TLS and token checks still happen at the frontend. Requires the AWS Load Balancer Controller. | `bool` | `false` | no |
| frontend_nlb_name | Name of the NLB, unique in the account and region. When null, &lt;cluster name&gt;-&lt;name&gt;, cut to 32 characters. | `string` | `null` | no |
| frontend_nlb_subnet_ids | Private subnets for the NLB. When empty, the load balancer controller picks the subnets tagged kubernetes.io/role/internal-elb. | `list(string)` | `[]` | no |
| frontend_nlb_source_cidrs | CIDR blocks allowed to reach the NLB. They are also admitted to the frontend by the network policy, since the NLB keeps client addresses. | `list(string)` | `[]` | no |
| frontend_nlb_cross_zone_enabled | Spread NLB traffic across frontend pods in every zone, not only the client's zone. Cross-zone traffic is charged. | `bool` | `true` | no |
| frontend_nlb_deletion_protection_enabled | Protect the NLB from deletion. Turn it off before removing the NLB. | `bool` | `false` | no |
| tailscale_frontend_enabled | Put the frontend's gRPC port on your tailnet through the Tailscale Kubernetes operator. TCP passes straight through, so TLS and token checks still happen at the frontend. | `bool` | `false` | no |
| tailscale_frontend_hostname | Tailnet device name for the frontend. When null, &lt;name&gt;-frontend. | `string` | `null` | no |
| tailscale_frontend_tags | Tailscale tags for the frontend's device, such as tag:workflows-grpc. When empty, the operator's default tags. Grant access to the tag in your tailnet policy. | `list(string)` | `[]` | no |
| tailscale_web_enabled | Serve the Web UI on your tailnet over HTTPS through the Tailscale Kubernetes operator's Ingress. | `bool` | `false` | no |
| tailscale_web_hostname | Tailnet device name for the Web UI. When null, the release name. | `string` | `null` | no |
| tailscale_web_tags | Tailscale tags for the Web UI's device. When empty, the operator's default tags. Grant access to the tag in your tailnet policy. | `list(string)` | `[]` | no |
| tailscale_namespace | Namespace the Tailscale operator runs its proxies in. The network policies admit it to the frontend and the Web UI. | `string` | `"tailscale"` | no |
| tailscale_tailnet_domain | Your tailnet's MagicDNS domain, such as example-tailnet.ts.net. Used to derive the tailnet addresses in the outputs and the Web UI's OIDC callback URL. | `string` | `null` | no |
| web_oidc_enabled | Require sign-in to the Web UI through an OpenID Connect provider. | `bool` | `false` | no |
| web_oidc_provider | Identity provider preset. `google` fills the issuer URL and scopes; `okta` and `microsoft_entra` fill the scopes and need your organization's issuer URL; `generic` needs both. | `string` | `"google"` | no |
| web_oidc_issuer_url | OIDC issuer URL, overriding the preset: https://&lt;org&gt;.okta.com (or an authorization server) for Okta, https://login.microsoftonline.com/&lt;tenant ID&gt;/v2.0 for Microsoft Entra ID. | `string` | `null` | no |
| web_oidc_scopes | Scopes the Web UI requests, overriding the preset. | `list(string)` | `null` | no |
| web_oidc_client_secret_arn | Secrets Manager secret (JSON) holding the OIDC client ID and client secret, synced through External Secrets. | `string` | `null` | no |
| web_oidc_client_id_property | JSON key of the client ID in the secret. | `string` | `"client_id"` | no |
| web_oidc_client_secret_property | JSON key of the client secret in the secret. | `string` | `"client_secret"` | no |
| web_oidc_callback_url | Callback URL to register with the provider. When null, https://&lt;Web UI host&gt;/auth/sso/callback, from the Tailscale hostname and tailnet domain or the ingress host. | `string` | `null` | no |
| web_enabled | Run the Temporal Web UI. Without web_oidc_enabled it has no sign-in: anyone who can reach it can read and act on every namespace. | `bool` | `true` | no |
| web | Web UI replicas and resources. | `object` | `{}` | no |
| web_ingress_enabled | Expose the Web UI through an Ingress. With the default `alb` class it is an internal Application Load Balancer, reachable only from inside the VPC and networks connected to it. | `bool` | `false` | no |
| web_ingress_class_name | IngressClass for the Web UI. `alb` is the AWS Load Balancer Controller's. | `string` | `"alb"` | no |
| web_ingress_host | Host name the Web UI Ingress answers on. When null, every host. | `string` | `null` | no |
| web_ingress_certificate_arn | ACM certificate for HTTPS on the internal ALB (alb class only). When null, the ALB listens on HTTP 80. | `string` | `null` | no |
| web_ingress_annotations | Annotations merged over the module's Ingress annotations, for example to join a shared ALB with alb.ingress.kubernetes.io/group.name. | `map(string)` | `{}` | no |
| metrics_prometheus_annotations_enabled | Annotate the server pods with prometheus.io/scrape, for scrapers that discover pods by annotation. | `bool` | `true` | no |
| metrics_service_monitor_enabled | Create Prometheus Operator ServiceMonitors for the servers. Requires the monitoring.coreos.com CRDs. | `bool` | `false` | no |
| metrics_otlp_endpoint | OTLP gRPC endpoint (host:port or http://host:port) to push the servers' metrics to, such as the EKS Add-ons module's otlp_grpc_endpoint output. A small forwarder in the namespace scrapes the servers and pushes the samples. When null, no forwarder runs. | `string` | `null` | no |
| metrics_otlp_metric_families | Metric families the forwarder keeps, as regular expressions without the _bucket/_sum/_count/_total suffixes. Empty keeps everything, which can be many series on a busy cluster. | `list(string)` | `(curated list)` | no |
| metrics_otlp_collector_image | OpenTelemetry Collector image for the metrics forwarder. It must include the prometheus receiver and the otlp_grpc exporter. | `string` | `"otel/opentelemetry-collector-contrib:0.161.0"` | no |
| helm_values | Extra YAML values documents for the upstream Temporal chart, applied after the module's own values, for settings this module has no input for (Web UI sign-in, authorization, dynamic config). | `list(string)` | `[]` | no |
| helm_timeout_seconds | How long an install or upgrade waits for the schema job and every Temporal pod to be ready. | `number` | `900` | no |
| tags | A map of tags applied, as provider default tags, to any AWS resource the module creates. | `map(string)` | `{}` | no |

The service objects (`frontend`, `history`, `matching`, `worker`, `internal_frontend`, `web`) take `replicas`, `cpu_request`, `memory_request` and `memory_limit`; see `variables.tf` for their defaults. `node_pool` takes `ec2_node_class_name`, `capacity_types`, `instance_categories`, `architectures`, `cpu_limit` and `consolidate_after`.

## Outputs

| Name | Description |
|------|-------------|
| release_name | Name of the Temporal Helm release. Every Service it creates is prefixed with it. |
| namespace | Kubernetes namespace Temporal runs in. |
| chart_version | Version of the upstream Temporal chart installed. |
| frontend_address | In-cluster gRPC address of the Temporal frontend, host:port, for SDK clients and the CLI (TEMPORAL_ADDRESS). |
| frontend_host | In-cluster host name of the Temporal frontend Service. |
| frontend_port | gRPC port of the Temporal frontend. |
| frontend_http_address | In-cluster address of the frontend's HTTP API, host:port. |
| temporal_namespaces | Temporal namespaces the module creates and keeps configured. |
| jwt_auth_enabled | Whether the frontend requires a JWT on every call. |
| internal_frontend_address | In-cluster address of the internal frontend, for callers with an internode certificate (null unless JWT authorization is on). |
| frontend_nlb_hostname | DNS name of the frontend's internal NLB; clients connect to &lt;hostname&gt;:7233 (null unless the NLB is enabled). |
| tailscale_frontend_address | Tailnet address of the frontend's gRPC port, host:port: the MagicDNS name when tailscale_tailnet_domain is set, otherwise the device name (null unless enabled). |
| tailscale_web_url | Tailnet URL of the Web UI (null unless enabled with tailscale_tailnet_domain set). |
| web_oidc_callback_url | Callback (redirect) URL to register with the OIDC provider (null unless Web UI sign-in is on). |
| num_history_shards | Number of history shards the cluster was configured with. |
| web_address | In-cluster URL of the Web UI (null when the Web UI is off). |
| web_url | URL of the Web UI through its Ingress (null unless the Ingress is enabled with a host). |
| tls_enabled | Whether the frontend serves TLS. SDK clients must then connect with TLS. |
| tls_server_name | Name SDK clients verify the frontend certificate against (null when TLS is off). |
| tls_ca_secret_name | Kubernetes Secret in the namespace whose ca.crt is the CA SDK clients trust for the frontend, whichever CA issued it (null when TLS is off). Copy only ca.crt to clients: the Secret also holds the frontend's private key. |
| tls_ca_source | Certificate authority behind the frontend and internode certificates: self_signed, issuer or secret (null when TLS is off). |
| tls_issuer | cert-manager issuer that signs the frontend and internode certificates, as {name, kind, group} (null when TLS is off). |
| database_endpoint | Endpoint of the Aurora cluster Temporal uses. |
| database_secret_name | Kubernetes Secret holding the database password. |
| priority_class_name | PriorityClass the Temporal pods run with (null when none). |
| node_pool_name | Dedicated Karpenter NodePool Temporal runs on (null when not created). |
