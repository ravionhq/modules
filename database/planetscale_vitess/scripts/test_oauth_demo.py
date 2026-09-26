"""Offline checks for the shell demo's embedded Python OAuth lifecycle."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs


class OAuthDemoTest(unittest.TestCase):
    def test_login_reuse_refresh_and_runner_handoff(self):
        script = Path(__file__).with_name("try_oauth_service_token.sh").read_text()
        source = script.split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
        namespace = {"__name__": "oauth_demo_test"}
        exec(compile(source, "oauth_demo", "exec"), namespace)
        requests = []

        def request(url, body, headers, label, method="POST"):
            requests.append((url, body, headers, method))
            if method == "GET":
                return {"name": "example"}
            if url.endswith("/service-tokens"):
                self.assertEqual(headers["Authorization"], "Bearer next-access")
                self.assertEqual(json.loads(body)["ttl"], 900)
                return {"id": "service-id", "token": "service-secret", "expires_at": "future"}
            fields = parse_qs(body.decode())
            if fields["grant_type"] == ["authorization_code"]:
                self.assertEqual(fields["code"], ["callback-code"])
                return {"access_token": "first-access", "refresh_token": "first-refresh", "expires_in": 3600,
                        "scope": "organization:read_organization"}
            self.assertEqual(fields["refresh_token"], ["first-refresh"])
            return {"access_token": "next-access", "refresh_token": "rotated-refresh", "expires_in": 7200}

        namespace["api_request"] = request
        namespace["capture_code"] = lambda *_: "callback-code"
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "credentials.json"
            env = {
                "PLANETSCALE_ORGANIZATION": "example",
                "PLANETSCALE_CLIENT_ID": "test-client",
                "PLANETSCALE_CLIENT_SECRET": "client-secret",
                "PLANETSCALE_OAUTH_CREDENTIALS_FILE": str(cache),
            }
            with patch.dict(os.environ, env, clear=True):
                def run(mode):
                    out, err = io.StringIO(), io.StringIO()
                    with patch("sys.argv", ["demo", mode]), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                        namespace["main"]()
                    self.assertNotIn("refresh", out.getvalue())
                    self.assertNotIn("client-secret", out.getvalue() + err.getvalue())
                    return out.getvalue()

                self.assertEqual(run("--login"), "export PLANETSCALE_OAUTH_ACCESS_TOKEN=first-access\n")
                self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
                self.assertEqual(len(requests), 2)
                self.assertEqual(run(""), "export PLANETSCALE_OAUTH_ACCESS_TOKEN=first-access\n")
                self.assertEqual(len(requests), 3)  # reuse: only direct API call
                self.assertEqual(run("--refresh"), "export PLANETSCALE_OAUTH_ACCESS_TOKEN=next-access\n")
                self.assertEqual(json.loads(cache.read_text())["refresh_token"], "rotated-refresh")
                self.assertEqual(json.loads(cache.read_text())["scope"], "organization:read_organization")
                self.assertEqual(requests[-1][2]["Authorization"], "Bearer next-access")
                # Force expiry and prove automatic refresh uses the cached grant.
                saved = json.loads(cache.read_text())
                saved.update(expires_at=0, refresh_token="first-refresh")
                cache.write_text(json.dumps(saved))
                self.assertEqual(run(""), "export PLANETSCALE_OAUTH_ACCESS_TOKEN=next-access\n")
                self.assertEqual(len(requests), 7)
                self.assertFalse(any("service-tokens" in req[0] for req in requests))
                self.assertEqual(run("--service-token"),
                                 "export PLANETSCALE_SERVICE_TOKEN_ID=service-id\n"
                                 "export PLANETSCALE_SERVICE_TOKEN=service-secret\n")


if __name__ == "__main__":
    unittest.main()
