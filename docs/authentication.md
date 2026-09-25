# Authentication boundary and local OIDC qualification

The core adapter resolves an independently verified OIDC identity to an existing,
active principal by the exact pair `(issuer, subject)`. The issuer is server
configuration; the subject is the verified proxy's `X-Forwarded-User`, not an email,
display name, browser input, URL parameter, or client-provided role. Accounts are
provisioned separately and are never automatically created on login.

`new_authentication_config()` requires a private gateway secret, explicit transport
peer addresses, and a maximum actor lifetime (default 15 minutes, maximum one
hour). `authenticated_actor(repo, session$request, config)` checks all three
boundary conditions before querying the current principal. Missing or spoofed
headers, unknown identities and disabled accounts fail closed. Every existing
service still checks current principal, membership and capability state. Actor
expiry is a cap on one Shiny session, not a claim that IdP-wide logout instantly
terminates every websocket or that OIDC authentication age was independently
revalidated by R.

The application uses a trusted `actor_factory(session, repo)` once for each
session and a `repo_factory()` for a separate connection, closed at session end.
The fixed-actor demonstration interface remains separate. Neither mock request
objects nor unit tests qualify an OIDC deployment.

## Actual local gateway

`deploy/auth/compose.yaml` pins inspected image digests for Keycloak 26.7.4,
OAuth2 Proxy 7.15.4, nginx, and Rocker Shiny 4.6.1. Only the proxy on
`127.0.0.1:4189` and IdP on `127.0.0.1:4190` are published. A dedicated nginx
hop accepts only the proxy's fixed container address, overwrites the private
`X-Delphyr-Gateway` header, and removes authorization/access-token headers. The
application is on a separate internal network with no published application port.
Its internal port is 3860. The existing synthetic database is attached to that
internal network with an explicit alias; no unrelated containers are modified.

OAuth2 Proxy performs the authorization-code flow, S256 PKCE, nonce checking,
issuer/audience verification and signed session-cookie handling. Its OIDC User
claim is `sub`; email preference is disabled. It strips incoming authentication
headers before setting verified identity headers. Browser-forged identity headers
must not change the mapped principal. nginx's secret is additional origin
protection, not an implementation of OIDC or a browser credential.

All credentials are generated into ignored `.local/auth`, whose directory is
mode 0700. Container-mounted secret files need read permission inside the
container; their containing host directory remains private. The deployment is
synthetic development only: HTTP loopback, development-mode Keycloak and an
insecure-cookie exception are deliberate local test settings. They are not
production guidance. There is no SMTP configuration or real-message transport.

## Stock Shiny Server OSS result: not qualified

The actual Rocker image runs Shiny Server OSS 1.5.24.1038. A real browser completed
Keycloak login through OAuth2 Proxy, but the R session received neither custom
identity header. The adapter rejected the session, as intended. The shipped
`lib/proxy/sockjs.js` opens the worker websocket without forwarding custom headers;
the SockJS transport additionally filters its request headers. The
`whitelist_headers` directive is not supported by this OSS build and causes
startup failure. It was removed from the runnable configuration.

Therefore, a functioning login page or an issued gateway cookie does **not** prove
an authenticated Shiny session in stock OSS. This fixture preserves that negative
qualification result. No identity-in-URL bridge, browser principal selection, or
unreviewed patch to Shiny Server is used to bypass the missing transport contract.
Stock Shiny Server OSS authentication remains an open acceptance gate.

## Local setup

From the repository root, prepare the private fixture once:

```sh
python3 deploy/auth/prepare.py
Rscript deploy/auth/provision.R
docker compose -f deploy/auth/compose.yaml build app
docker compose -f deploy/auth/compose.yaml up -d
docker network connect --alias delphyr-auth-db delphyr-auth-back delphyr-dev-postgres
```

The provisioner uses the owner connection only to create the synthetic fixture
and register its issuer/subject mapping. The running application uses
`delphyr_runtime`. Run `scripts/configure-dev-role.R` after new migrations as
specified in the development setup. Existing generated credentials are preserved;
`prepare.py` refuses to overwrite an active realm fixture. Read the synthetic
username/password locally from `.local/auth/credentials.json`; never copy that
file into documentation, screenshots, terminal reports, or Git.

The database network attachment command is only needed once. Stopping this stack
must not remove the existing database container or its volume. Detach the database
from `delphyr-auth-back` before removing that network. The auth realm itself is
recreated from the private synthetic fixture when its container is recreated.

## Qualified local alternative: direct Shiny behind the same gateway

An explicit alternative uses `shiny::runApp()` inside the same unexposed app
container, running as the unprivileged `shiny` account. This is **not** Shiny Server
OSS qualification. It preserves HTTP/websocket headers and admits only nginx's
fixed backend transport address plus its private secret. Start it with:

```sh
docker compose -f deploy/auth/compose.yaml -f deploy/auth/compose.direct.yaml up -d app
```

The real Chromium test completed OIDC login and resolved the authenticated stable
subject to the exact database study. Twelve checks passed: unauthenticated and
forged-header requests, malformed cookies, invalid callback state, direct gateway
rejection, no published app port, successful identity mapping, authenticated
subject-header spoof resistance, a separate unassigned user's session, direct app
forgery rejection, current-principal revocation during an existing session, and
rejection of a new session for the disabled principal. The revocation probe uses
only the synthetic account and restores its active flag in a `finally` block.

To reproduce the browser evidence using the system Chromium binary:

```sh
python3 -m venv .local/auth/venv
.local/auth/venv/bin/pip install playwright requests beautifulsoup4
.local/auth/venv/bin/python deploy/auth/verify-browser.py
```

The fixture also contains `synthetic-no-study`, an independently authenticated
account with no memberships. Its private credentials are in
`.local/auth/second-credentials.json`. Tests never print passwords, cookies, tokens
or gateway secrets. Sanitized outcomes are saved to
`.local/auth/qualification.json`; screenshots contain synthetic UI data only.

The negative OSS test is independently reproducible:

```sh
docker compose -f deploy/auth/compose.yaml up -d app
.local/auth/venv/bin/python deploy/auth/verify-oss.py
docker compose -f deploy/auth/compose.yaml -f deploy/auth/compose.direct.yaml up -d app
```

It checks both successful gateway login and actual missing headers in the rejected
OSS websocket session, saving `.local/auth/oss-negative.json`. The installed OSS
websocket proxy file was byte-identical to the
[official source at commit 5334faa](https://github.com/rstudio/shiny-server/blob/5334faa37b2e5b803af97719b82472ecaffe9776/lib/proxy/sockjs.js).
The direct profile is left running after the test sequence; switch profiles only
when no interactive synthetic session is in use.

## Required evidence and remaining gates

Adapter tests cover absent/forged headers, invalid transport peers, issuer/subject
mapping, unknown accounts, ignored browser identity fields, active-account
revocation, no implicit study rights, and actor expiry. These are useful boundary
tests, separate from the real gateway qualification.

An accepted hosting path must additionally demonstrate a real browser login,
websocket identity propagation, forged-header resistance, unauthenticated and
direct-app rejection, current-right revocation and per-session isolation. Local
HTTP evidence does not qualify production TLS, institutional account lifecycle,
MFA policy, central logout, reverse-proxy replacement, or production network and
secret management. Production remains disabled by the core protocol validator.

## Official references checked

- [OAuth2 Proxy configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/)
  defines the proxy, header, cookie and PKCE settings.
- [OAuth2 Proxy 7.15.4 claim mapping source](https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.4/providers/provider_data.go)
  establishes the default `sub` to session User mapping.
- [Keycloak container guide](https://www.keycloak.org/server/containers) documents
  development mode and realm import, with development-mode limitations.
- [Rocker versioned Shiny images](https://rocker-project.org/images/versioned/shiny.html)
  identifies the actual Shiny Server image family.
- [Shiny Server reference](https://docs.posit.co/shiny-server/) distinguishes
  product-specific configuration. Actual OSS behavior was checked in the running
  image, rather than inferred from Pro documentation.
