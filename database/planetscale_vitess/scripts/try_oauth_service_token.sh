#!/usr/bin/env bash
# Demo the OAuth connection -> execution access-token flow without a proxy.
# Requires Python 3. Credentials are read from environment variables only.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: bash try_oauth_service_token.sh [--login | --refresh | --service-token]

Required environment variables:
  PLANETSCALE_ORGANIZATION       Target organization slug

Loads .env.local next to this script automatically (a trusted shell config file).
OAuth app configuration:
  PLANETSCALE_CLIENT_ID
  PLANETSCALE_CLIENT_SECRET
  PLANETSCALE_REDIRECT_URI       Exact registered OAuth callback URL; defaults to
                                http://127.0.0.1:8765/oauth/callback

Optional:
  PLANETSCALE_TOKEN_TTL          Service-token TTL in seconds (default 900;
                                this probe allows 1–3600)
  PLANETSCALE_AUTHORIZATION_CODE Skip the browser flow using an existing code
  PLANETSCALE_CALLBACK_PORT      Local listener port for an HTTPS tunnel (8765)
  PLANETSCALE_OAUTH_SCOPES        Optional space-separated scopes to request;
                                must be allowed by the OAuth app configuration
  PLANETSCALE_OAUTH_CREDENTIALS_FILE  Private JSON credential cache path
                                (default: ~/.local/state/ravion-planetscale-demo/
                                 <client-id>-<organization>.json)

Default: reuse saved credentials, refresh if less than five minutes remain,
or start browser authorization if there is no cache.
--login: reconnect through browser authorization, replacing the cached grant.
--refresh: force a refresh-token exchange to demonstrate later executions.
--service-token: use the saved OAuth connection to attempt creation of an
expiring service token. Output its ID/secret as shell exports instead of OAuth.
This does not assign permissions; successful creation alone does not prove
the token is ready for Terraform. The token is left to expire at its TTL.

The script starts a loopback callback server and opens PlanetScale authorization
in your browser. It validates state and waits up to five minutes for consent.
Register the redirect URI in PlanetScale first. If PlanetScale requires HTTPS,
tunnel to local port 8765 and set the URI to https://<tunnel-host>/oauth/callback.

Example (prompts avoid putting the secret in shell history):
  export PLANETSCALE_ORGANIZATION=your-org
  export PLANETSCALE_CLIENT_ID=your-client-id
  export PLANETSCALE_REDIRECT_URI=http://127.0.0.1:8765/oauth/callback
  read -r -s -p 'Client secret: ' PLANETSCALE_CLIENT_SECRET; echo
  export PLANETSCALE_CLIENT_SECRET
  umask 077
  bash try_oauth_service_token.sh > /path/outside/repo/planetscale-token.env

On success stdout exports only PLANETSCALE_OAUTH_ACCESS_TOKEN for the runner.
The refresh token stays in the private JSON cache (mode 0600). This cache models
Ravion's backend storage; never send it or .env.local to a remote runner.
The script checks organization access directly using Bearer authentication.
Enable organization read_organization in the OAuth app. Only --service-token
creates a resource. Direct OAuth use by Terraform still needs provider support.
Token lifetime is assigned by PlanetScale, not by this script.
Run one instance at a time to avoid concurrent refresh-token rotation.
HELP
  exit 0
fi

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--login" && "$1" != "--refresh" && "$1" != "--service-token" ) ]]; then
  echo 'Expected --login, --refresh, --service-token, or no argument. Use --help.' >&2
  exit 2
fi

env_file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/.env.local"
if [[ -f "$env_file" ]]; then
  set -a
  source "$env_file"
  set +a
fi

exec python3 - "${1:-}" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        fail(f"Missing {name}. Run this script with --help for instructions.")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    # Never forward authorization headers or client credentials to a redirect.
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(NoRedirect())


def capture_code(client_id, redirect_uri):
    uri = urllib.parse.urlsplit(redirect_uri)
    if uri.query or uri.fragment or uri.username or uri.password or not uri.path:
        fail("Redirect URI must have a callback path and no query, fragment or credentials.")
    try:
        if uri.scheme == "http" and uri.hostname in ("127.0.0.1", "localhost"):
            port = uri.port or 80
        elif uri.scheme == "https" and uri.hostname:
            port = int(os.environ.get("PLANETSCALE_CALLBACK_PORT", "8765"))
        else:
            fail("Use an HTTP localhost/127.0.0.1 callback or an HTTPS tunnel URL.")
        if not 1 <= port <= 65535:
            raise ValueError()
    except ValueError:
        fail("Invalid callback port.")
    state = secrets.token_urlsafe(32)
    result = {}

    class Callback(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Callback URLs contain authorization codes.

        def do_GET(self):
            target = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(target.query)
            status, message = 400, "Invalid callback. Return to your terminal."
            if target.path != uri.path:
                status, message = 404, "Not found."
            elif len(query.get("state", [])) != 1 or not secrets.compare_digest(
                query["state"][0].encode(), state.encode()
            ):
                message = "Invalid OAuth state. Use the authorization link from your terminal."
            elif "error" in query:
                result["error"] = True
                message = "Authorization was denied or failed. Return to your terminal."
            elif len(query.get("code", [])) == 1:
                result["code"] = query["code"][0]
                status, message = 200, "Authorization received. You can close this tab and return to your terminal."
            self.send_response(status)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(message.encode())

    try:
        server = HTTPServer(("127.0.0.1", port), Callback)
    except OSError:
        fail(f"Cannot listen on 127.0.0.1:{port}; check whether the port is already in use.")
    authorization_fields = {
        "client_id": client_id, "redirect_uri": redirect_uri, "state": state,
        "response_type": "code",
    }
    requested_scopes = os.environ.get("PLANETSCALE_OAUTH_SCOPES", "").strip()
    if requested_scopes:
        authorization_fields["scope"] = requested_scopes
    url = "https://auth.planetscale.com/oauth/authorize?" + urllib.parse.urlencode(authorization_fields)
    with server:
        server.timeout = 1
        # Bound the time spent reading an incomplete inbound request too.
        original_get_request = server.get_request
        def get_request():
            connection, address = original_get_request()
            connection.settimeout(2)
            return connection, address
        server.get_request = get_request
        print(f"Listening on http://127.0.0.1:{port}{uri.path}", file=sys.stderr)
        print(f"Authorize in your browser:\n{url}", file=sys.stderr)
        try:
            webbrowser.open(url)
        except webbrowser.Error:
            pass  # The printed URL can be opened manually.
        deadline = time.monotonic() + 300
        while not result and time.monotonic() < deadline:
            server.handle_request()
    if result.get("error"):
        fail("PlanetScale authorization was denied or failed.")
    if not result.get("code"):
        fail("Timed out waiting for OAuth callback. Check the registered redirect URI and tunnel, if used.")
    return result["code"]


def api_request(url, body, headers, label, method="POST"):
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with opener.open(request, timeout=30) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        # Report only a machine-readable error code, never raw response bodies
        # or free-text descriptions that could contain credentials.
        error_code = None
        try:
            payload = json.loads(error.read(65536))
            if isinstance(payload, dict):
                candidate = payload.get("code") or payload.get("error")
                if isinstance(candidate, str) and re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_:.\-]{0,79}", candidate):
                    if not candidate.startswith("pscale_"):
                        error_code = candidate
        except (ValueError, OSError):
            pass
        hints = {
            400: "Check the request fields; an authorization code may be invalid or already used.",
            401: "Authentication was rejected; check the OAuth credentials/access token.",
            403: "Access was denied. The OAuth grant may lack permission for this operation.",
            404: "Check the organization slug and the grant's access to that organization.",
            422: "PlanetScale rejected the request fields.",
            429: "Rate limited. Retry later with an appropriate OAuth credential.",
        }
        detail = f" API error code: {error_code}." if error_code else ""
        if error_code == "invalid_token" and label == "Organization access check":
            fail(f"{label}: HTTP {error.code}.{detail} "
                 "The API rejected the issued OAuth token. Check the OAuth app's "
                 "allowed scopes and authorized resources, then run --login to "
                 "obtain a new grant. Refresh alone does not add permissions.")
        fail(f"{label}: HTTP {error.code}.{detail} " + hints.get(error.code, "Request failed.")
             + " Response body omitted to avoid exposing secrets.")
    except (urllib.error.URLError, TimeoutError, OSError):
        fail(f"{label}: network failure. No automatic retry was attempted; "
             "a create request may have succeeded, so check PlanetScale before retrying.")
    except (ValueError, UnicodeError):
        fail(f"{label}: invalid JSON response; response body omitted.")
    if not isinstance(data, dict):
        fail(f"{label}: unexpected response shape.")
    return data


def save_credentials(path, credentials):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".oauth-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as file:
            json.dump(credentials, file)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    ttl = 900
    if mode == "--service-token":
        try:
            ttl = int(os.environ.get("PLANETSCALE_TOKEN_TTL", "900"))
            if not 1 <= ttl <= 3600:
                raise ValueError()
        except ValueError:
            fail("This probe requires PLANETSCALE_TOKEN_TTL between 1 and 3600 seconds.")
    organization = required("PLANETSCALE_ORGANIZATION")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", organization):
        fail("PLANETSCALE_ORGANIZATION must be a lowercase organization slug.")
    client_id = required("PLANETSCALE_CLIENT_ID")
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", client_id):
        fail("Invalid PLANETSCALE_CLIENT_ID.")
    default_path = Path.home() / ".local/state/ravion-planetscale-demo" / f"{client_id}-{organization}.json"
    path = Path(os.environ.get("PLANETSCALE_OAUTH_CREDENTIALS_FILE") or default_path).expanduser()
    credentials = None
    if mode != "--login" and path.exists():
        if path.is_symlink() or path.stat().st_mode & 0o077:
            fail("Credential cache must be a private regular file. Set its permissions to 0600.")
        try:
            credentials = json.loads(path.read_text())
            if not isinstance(credentials, dict) or credentials.get("client_id") != client_id or credentials.get("organization") != organization:
                raise ValueError()
            if not isinstance(credentials.get("access_token"), str) or not credentials["access_token"]:
                raise ValueError()
            if not isinstance(credentials.get("expires_at"), (int, float)):
                raise ValueError()
        except (ValueError, OSError):
            fail("Invalid or mismatched credential cache. Run --login to reconnect.")
    if mode == "--refresh" and not credentials:
        fail("No saved connection. Run --login first.")

    if not credentials or mode == "--refresh" or credentials["expires_at"] <= time.time() + 300:
        fields = {"client_id": client_id, "client_secret": required("PLANETSCALE_CLIENT_SECRET")}
        if credentials:
            refresh_token = credentials.get("refresh_token")
            if not isinstance(refresh_token, str) or not refresh_token:
                fail("No refresh token was issued. Run --login to reconnect.")
            fields.update(grant_type="refresh_token", refresh_token=refresh_token)
            print("Refreshing the saved OAuth connection...", file=sys.stderr)
        else:
            redirect_uri = os.environ.get("PLANETSCALE_REDIRECT_URI", "").strip() or "http://127.0.0.1:8765/oauth/callback"
            fields.update(grant_type="authorization_code", redirect_uri=redirect_uri)
            fields["code"] = os.environ.get("PLANETSCALE_AUTHORIZATION_CODE", "").strip() or capture_code(client_id, redirect_uri)
            print("Exchanging the authorization code...", file=sys.stderr)
        issued_at = time.time()
        response = api_request(
            "https://auth.planetscale.com/oauth/token", urllib.parse.urlencode(fields).encode(),
            {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
            "OAuth exchange (use --login if the saved refresh grant is invalid)",
        )
        access_token = response.get("access_token")
        if not isinstance(access_token, str) or not access_token:
            fail("OAuth exchange returned no access_token.")
        try:
            lifetime = int(response["expires_in"])
            if lifetime <= 0:
                raise ValueError()
        except (KeyError, TypeError, ValueError):
            fail("OAuth exchange returned no valid expires_in.")
        credentials = {
            "client_id": client_id, "organization": organization,
            "access_token": access_token,
            "refresh_token": response.get("refresh_token") or (credentials or {}).get("refresh_token"),
            "expires_at": issued_at + lifetime,
            "scope": response.get("scope", (credentials or {}).get("scope")),
        }
        # Save rotated refresh credentials before making any further API calls.
        save_credentials(path, credentials)
        print(f"Saved OAuth connection to {path} (private file).", file=sys.stderr)
        if credentials["scope"] in ("", []):
            fail("PlanetScale issued a token with no granted scopes. Enable access "
                 "scopes in your OAuth app, optionally set PLANETSCALE_OAUTH_SCOPES, "
                 "and run --login again. Refreshing cannot add missing permissions.")
    else:
        print("Reusing the unexpired access token from the saved connection.", file=sys.stderr)

    access_token = credentials["access_token"]
    print("Calling PlanetScale directly with the execution access token...", file=sys.stderr)
    api_request(
        f"https://api.planetscale.com/v1/organizations/{organization}", None,
        {"Authorization": f"Bearer {access_token}", "Accept": "application/json"},
        "Organization access check", method="GET",
    )
    remaining = max(0, int(credentials["expires_at"] - time.time()))
    if mode == "--service-token":
        print(f"OAuth organization access succeeded. Trying service-token creation (TTL: {ttl}s)...", file=sys.stderr)
        response = api_request(
            f"https://api.planetscale.com/v1/organizations/{organization}/service-tokens",
            json.dumps({"name": f"ravion-oauth-probe-{int(time.time())}", "ttl": ttl}).encode(),
            {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json",
             "Accept": "application/json"},
            "Service-token creation",
        )
        token_id, token = response.get("id"), response.get("token")
        if not isinstance(token_id, str) or not token_id or not isinstance(token, str) or not token:
            fail("Creation returned no usable id/token pair. Check PlanetScale for a created token.")
        print(f"Service token created. Returned expiry: {response.get('expires_at', 'not provided')}. "
              "Permissions have not been assigned or tested.", file=sys.stderr)
        print(f"export PLANETSCALE_SERVICE_TOKEN_ID={shlex.quote(token_id)}")
        print(f"export PLANETSCALE_SERVICE_TOKEN={shlex.quote(token)}")
        return
    print(f"Organization access succeeded. Access token has about {remaining} seconds remaining.\n"
          "Only the access token is exported for the runner; refresh credentials stay in the cache.", file=sys.stderr)
    print(f"export PLANETSCALE_OAUTH_ACCESS_TOKEN={shlex.quote(access_token)}")


if __name__ == "__main__":
    main()
PY
