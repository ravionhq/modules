"""Read live EKS scaling for Terraform's external data source; never mutate AWS."""

import json
import re
import subprocess
import sys


def read_scaling(query):
    region = query["region"]

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

    result = aws(
        "eks", "describe-nodegroup", "--cluster-name", query["cluster_name"],
        "--nodegroup-name", query["node_group_name"],
    )
    if result.returncode:
        # Only an explicit EKS not-found means first creation. Authentication,
        # networking, throttling, and permission failures must stop the plan.
        if re.search(
            r"An error occurred \(ResourceNotFoundException\) when calling the DescribeNodegroup operation:",
            result.stderr,
        ):
            return {"exists": "false", "desired_size": "0"}
        raise RuntimeError(result.stderr.strip())

    nodegroup = json.loads(result.stdout)["nodegroup"]
    arn = nodegroup["nodegroupArn"].split(":")
    if len(arn) < 6 or arn[3] != region or arn[4] != query["account_id"]:
        raise RuntimeError("EKS node group does not match the provider account and region")
    desired = nodegroup["scalingConfig"]["desiredSize"]
    if type(desired) is not int or desired < 0:
        raise RuntimeError("EKS returned an invalid desiredSize")
    return {"exists": "true", "desired_size": str(desired)}


if __name__ == "__main__":
    try:
        print(json.dumps(read_scaling(json.load(sys.stdin))))
    except (KeyError, ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"Unable to read EKS node group scaling: {error}", file=sys.stderr)
        sys.exit(1)
