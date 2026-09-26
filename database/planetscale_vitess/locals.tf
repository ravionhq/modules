locals {
  default_keyspace_name = one([
    for keyspace in data.planetscale_vitess_keyspaces.main.data : keyspace.name if keyspace.is_default
  ])

  # URI escaping is important for credentials and database names. MySQL driver
  # TLS options differ, so TLS is provided separately rather than a fake
  # universal sslmode parameter.
  connection_string = format("mysql://%s:%s@%s:3306/%s",
    urlencode(planetscale_vitess_branch_password.application.username),
    urlencode(planetscale_vitess_branch_password.application.plain_text),
    planetscale_vitess_branch_password.application.access_host_url,
    urlencode(var.name)
  )
}
