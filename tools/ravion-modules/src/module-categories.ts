export interface ModuleCategorySpec {
  givenId: string;
  name: string;
  description: string;
  sortOrder: number;
  definitionTypes: readonly string[];
  previousGivenIds?: readonly string[];
}

export const MODULE_CATEGORIES: readonly ModuleCategorySpec[] = [
  {
    givenId: "web-server",
    name: "Web server",
    description: "For websites, HTTP APIs, and services reached through a browser or web client.",
    sortOrder: 10,
    definitionTypes: ["rvn-ec2-service", "rvn-ecs-nlb", "rvn-ecs-web", "rvn-eks-web"],
  },
  {
    givenId: "tcp-udp-server",
    name: "TCP/UDP server",
    description: "For Layer 4 workloads such as game servers, MQTT brokers, and custom TCP, UDP, or TLS protocols.",
    sortOrder: 20,
    definitionTypes: ["rvn-ecs-nlb"],
    previousGivenIds: ["tcp-udp-service"],
  },
  {
    givenId: "worker",
    name: "Worker",
    description: "For queue consumers, scheduled jobs, and background processes without public endpoints.",
    sortOrder: 30,
    definitionTypes: ["rvn-ec2-service", "rvn-ecs-worker", "rvn-eks-cron", "rvn-eks-worker"],
  },
  {
    givenId: "function",
    name: "Function",
    description: "For webhook handlers, scheduled tasks, and event processing that run only when invoked.",
    sortOrder: 40,
    definitionTypes: ["rvn-lambda"],
  },
  {
    givenId: "static-site",
    name: "Static site",
    description: "For frontend assets, documentation, and single-page apps that do not need an always-on server.",
    sortOrder: 50,
    definitionTypes: ["rvn-aws-static"],
  },
  {
    givenId: "database",
    name: "Database",
    description: "For relational data such as PostgreSQL or MySQL, including connection pooling.",
    sortOrder: 60,
    definitionTypes: ["rvn-aurora", "rvn-rds", "rvn-rds-proxy"],
  },
  {
    givenId: "cache",
    name: "Cache",
    description: "For Redis or Memcached workloads that need low-latency shared state.",
    sortOrder: 70,
    definitionTypes: ["rvn-elasticache"],
  },
  {
    givenId: "storage",
    name: "Storage",
    description: "For uploads, backups, and shared files that need persistent object or file storage.",
    sortOrder: 80,
    definitionTypes: ["rvn-efs", "rvn-s3"],
  },
  {
    givenId: "cluster",
    name: "Cluster",
    description: "For services that share container capacity, load balancers, and placement configuration.",
    sortOrder: 90,
    definitionTypes: ["rvn-ecs-cluster", "rvn-eks-cluster", "rvn-eks-addons"],
  },
  {
    givenId: "network",
    name: "Network",
    description: "For private subnets, internet access, service connectivity, and shared load balancers.",
    sortOrder: 100,
    definitionTypes: ["rvn-aws-alb", "rvn-aws-network"],
  },
  {
    givenId: "domain",
    name: "Domain",
    description: "For custom domains, DNS records, and HTTPS certificates.",
    sortOrder: 110,
    definitionTypes: ["rvn-acm-certificate", "rvn-route53"],
  },
  {
    givenId: "cdn",
    name: "CDN",
    description: "For serving images, JavaScript bundles, and downloads closer to users.",
    sortOrder: 120,
    definitionTypes: ["rvn-cloudfront"],
  },
  {
    givenId: "security",
    name: "Security",
    description: "For identity, permissions, encryption keys, and least-privilege access.",
    sortOrder: 130,
    definitionTypes: ["rvn-aws-iam-policy", "rvn-aws-iam-role", "rvn-aws-kms"],
  },
  {
    givenId: "iac",
    name: "IaC",
    description: "For custom infrastructure that is not covered by a purpose-built module.",
    sortOrder: 140,
    definitionTypes: ["rvn-stack"],
  },
];

const MODULE_CATEGORIES_BY_DEFINITION_TYPE = new Map<string, ModuleCategorySpec[]>();
for (const category of MODULE_CATEGORIES) {
  for (const definitionType of category.definitionTypes) {
    const categories = MODULE_CATEGORIES_BY_DEFINITION_TYPE.get(definitionType) ?? [];
    categories.push(category);
    MODULE_CATEGORIES_BY_DEFINITION_TYPE.set(definitionType, categories);
  }
}

export function getModuleCategoriesForDefinitionType(
  definitionType: string,
): readonly ModuleCategorySpec[] {
  return MODULE_CATEGORIES_BY_DEFINITION_TYPE.get(definitionType) ?? [];
}
