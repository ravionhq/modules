#!/usr/bin/env python3
"""Make a Grafana workspace's module-owned data sources match DATA_SOURCES.

Each data source in DATA_SOURCES is created, or updated in place by its UID.
Every UID in MANAGED_UIDS that DATA_SOURCES leaves out is deleted. The script
signs in with a service account token it mints for this run and deletes when
done, so no credential outlives the run.

Environment: AWS_REGION, WORKSPACE_ID, SERVICE_ACCOUNT_ID, GRAFANA_URL,
DATA_SOURCES (JSON list of Grafana data source bodies), MANAGED_UIDS (JSON list).
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

TOKEN_SECONDS_TO_LIVE = 900
# A workspace that just turned ACTIVE can refuse requests for a short while.
ATTEMPTS = 20
ATTEMPT_INTERVAL_SECONDS = 6


def log(message):
    print(f"Grafana data sources: {message}", flush=True)


def aws(*args):
    result = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.exit(f"Grafana data sources: aws {' '.join(args[:2])} failed: {result.stderr.strip()}")
    return json.loads(result.stdout) if result.stdout.strip() else {}


class Grafana:
    def __init__(self, url, token):
        self.url = url.rstrip("/")
        self.token = token

    def request(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(1, ATTEMPTS + 1):
            request = urllib.request.Request(self.url + path, data=data, method=method, headers={
                "Authorization": "Bearer " + self.token,
                "Content-Type": "application/json",
                "Accept": "application/json",
            })
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    return response.status
            except urllib.error.HTTPError as error:
                if error.code < 500 and error.code != 429:
                    if error.code != 404:
                        detail = error.read().decode(errors="replace")[:500]
                        sys.exit(f"Grafana data sources: {method} {path} returned {error.code}: {detail}")
                    return error.code
                reason = f"HTTP {error.code}"
            except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                reason = str(error)
            if attempt == ATTEMPTS:
                sys.exit(f"Grafana data sources: {method} {path} kept failing: {reason}")
            log(f"{method} {path} failed ({reason}); retrying")
            time.sleep(ATTEMPT_INTERVAL_SECONDS)
        return None


def main():
    workspace_id = os.environ["WORKSPACE_ID"]
    service_account_id = os.environ["SERVICE_ACCOUNT_ID"]
    wanted = json.loads(os.environ["DATA_SOURCES"])
    managed_uids = json.loads(os.environ["MANAGED_UIDS"])

    minted = aws(
        "grafana", "create-workspace-service-account-token",
        "--workspace-id", workspace_id,
        "--service-account-id", service_account_id,
        "--name", f"data-sources-{int(time.time())}",
        "--seconds-to-live", str(TOKEN_SECONDS_TO_LIVE),
    )["serviceAccountToken"]
    try:
        grafana = Grafana(os.environ["GRAFANA_URL"], minted["key"])
        for data_source in wanted:
            path = f"/api/datasources/uid/{data_source['uid']}"
            if grafana.request("GET", path) == 404:
                grafana.request("POST", "/api/datasources", data_source)
                log(f"created {data_source['uid']}")
            else:
                grafana.request("PUT", path, data_source)
                log(f"updated {data_source['uid']}")
        wanted_uids = {data_source["uid"] for data_source in wanted}
        for uid in managed_uids:
            if uid not in wanted_uids and grafana.request("DELETE", f"/api/datasources/uid/{uid}") != 404:
                log(f"removed {uid}")
    finally:
        aws(
            "grafana", "delete-workspace-service-account-token",
            "--workspace-id", workspace_id,
            "--service-account-id", service_account_id,
            "--token-id", minted["id"],
        )


if __name__ == "__main__":
    main()
