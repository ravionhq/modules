"""Read live EKS scaling for Terraform's external data source; never mutate AWS.

The node group is named "<name>-<generated suffix>" so it can be replaced
blue/green, and tagged ravion.com/node-group=<name>. A group created before
names were generated is named exactly <name> and has no tag. Both are found.
While a replacement is in flight both the old and new group exist; the larger
desired size wins so capacity is never planned down.
"""

import json
import re
import subprocess
import sys

NODE_GROUP_TAG = "ravion.com/node-group"


def read_scaling(query):
    region = query["region"]
    name = query["node_group_name"]

    def aws(*args):
        return subprocess.run(
            ["aws", "--region", region, "--output", "json", "--no-cli-pager",
             "--cli-connect-timeout", "10", "--cli-read-timeout", "30", *args],
            capture_output=True, text=True, timeout=60, check=False,
        )

    identity = aws("sts", "get-caller-identity")
    if identity.returncode:
        raise RuntimeError(identity.stderr.strip())
    if json.loads(identity.stdout)["Account"] != query["account_id"]:
        raise RuntimeError(
            "AWS CLI credentials do not match the Terraform AWS provider account. "
            "Supply the provider's target-account credentials to the runner environment."
        )

    listed = aws("eks", "list-nodegroups", "--cluster-name", query["cluster_name"])
    if listed.returncode:
        # Only an explicit EKS not-found (no cluster yet) means first creation.
        # Authentication, networking, throttling, and permission failures must
        # stop the plan.
        if re.search(
            r"An error occurred \(ResourceNotFoundException\) when calling the ListNodegroups operation:",
            listed.stderr,
        ):
            return {"exists": "false", "desired_size": "0"}
        raise RuntimeError(listed.stderr.strip())

    candidates = [
        group for group in json.loads(listed.stdout)["nodegroups"]
        if group == name or group.startswith(name + "-")
    ]

    desired_sizes = []
    for group in candidates:
        result = aws(
            "eks", "describe-nodegroup", "--cluster-name", query["cluster_name"],
            "--nodegroup-name", group,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        nodegroup = json.loads(result.stdout)["nodegroup"]
        # A prefixed name alone is not enough: "system-extra" is a different
        # group from "system". Only the tag, or the exact legacy name, counts.
        if group != name and (nodegroup.get("tags") or {}).get(NODE_GROUP_TAG) != name:
            continue
        arn = nodegroup["nodegroupArn"].split(":")
        if len(arn) < 6 or arn[3] != region or arn[4] != query["account_id"]:
            raise RuntimeError("EKS node group does not match the provider account and region")
        desired = nodegroup["scalingConfig"]["desiredSize"]
        if type(desired) is not int or desired < 0:
            raise RuntimeError("EKS returned an invalid desiredSize")
        desired_sizes.append(desired)

    if not desired_sizes:
        return {"exists": "false", "desired_size": "0"}
    return {"exists": "true", "desired_size": str(max(desired_sizes))}


if __name__ == "__main__":
    try:
        print(json.dumps(read_scaling(json.load(sys.stdin))))
    except (KeyError, ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"Unable to read EKS node group scaling: {error}", file=sys.stderr)
        sys.exit(1)
