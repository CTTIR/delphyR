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

The container fixture qualifies authentication, session isolation and the
operation of several application processes behind one gateway. Its private
export directory is a volume shared by the application processes; the check
builds an export with a worker step inside one container and downloads it
through another. It is separate from the host development worker and is not a
qualified worker or storage deployment.

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

The gateway hop sends every request of one verified account to the same
application process (`hash $http_x_forwarded_user consistent`), because a
session, its uploads and its downloads live in one process. `scale.py` sets the
number of processes; `compose.scale.yaml` starts them.

All credentials are generated into ignored `.local/auth`, whose directory is
mode 0700. Container-mounted secret files need read permission inside the
container; their containing host directory remains private. The deployment is
synthetic development only: HTTP loopback, development-mode Keycloak and an
insecure-cookie exception are deliberate local test settings. They are not
production guidance. There is no SMTP configuration or real-message transport.

## Sessions: lifetime, renewal and sign-out

Three lifetimes apply, and the shortest one decides.

| What | Where it is set | Fixture | Effect when it ends |
|---|---|---|---|
| Identity of one application session | `max_session_seconds` of `new_authentication_config()`, at most one hour | 15 minutes | Every further action in the open page is refused with "Your sign-in has expired. Reload the page and sign in again." Nothing is saved or changed. |
| Session of the gateway | `cookie_expire` of OAuth2 Proxy | 15 minutes | The next page load is sent to the identity provider. |
| Session at the identity provider | realm settings | 15 minutes idle, 30 minutes at most | Credentials are required again. |

- **Own rights** are checked before every protected action. Revoking a right,
  deactivating a membership or disabling an account takes effect with the next
  action of an open page, without any delay.
- **What the identity provider withdraws** (a disabled account, a central
  logout) reaches an open page when its identity ends, that is after
  `max_session_seconds` at the latest, and a new page load when the session of
  the gateway ends. The application does not ask the provider again in between.
  Choose both lifetimes as short as the institution requires; a participant
  who rates for longer than the identity lives reloads the page and continues
  with every confirmed answer in place.
- **Renewal** is a page load: within the session of the gateway it gives a new
  identity without a visit to the provider; after it, the provider is visited
  and signs the person in again without credentials while its own session lives.
- **Signing out**: `run_app(sign_out_url = )` shows a "Sign out" link. It ends
  every session of the account that the process holds, for example a second
  tab, and then follows the address. In the fixture this is `/oauth2/sign_out`
  of OAuth2 Proxy, which drops its cookie and, through `backend_logout_url`,
  ends the session at the provider; the next visit asks for credentials.
  Without that setting the provider would sign the person in again at once.
  A page of the same account held by another process, which the routing above
  prevents, would live until its identity ends.

## Several application processes

One process serves the sessions it holds one request at a time
([load qualification](load.md)); more people rating at once need more
processes. Behind the gateway this requires:

- **One process per account.** The gateway sends all requests of a verified
  account to one process. Uploads and downloads carry the address of their
  session and are answered only by the process that holds it.
- **One private export directory** for all application processes and the
  worker (`artifact_root`), not readable by the web server.
- **The same installed version** in every process. A process answers requests
  for the scripts and styles of the page from its start, so that a page
  delivered by one process is complete even if another one has just been
  started.
- **A fixed set of processes while people work.** A change of the set routes
  some accounts to another process. Their open pages keep their connection,
  but an upload or a download from such a page reaches a process that does not
  hold its session and fails. A reload starts a session on the new process and
  continues from the confirmed state. Change the set in a maintenance window.

Each process needs its own database connection per session; plan the
connection limit of the database for all processes and the worker together.

## Stock Shiny Server OSS result: not qualified

The actual Rocker image runs Shiny Server OSS 1.5.24.1038. A real browser completed
Keycloak login through OAuth2 Proxy, but the R session received neither custom
identity header; the check was repeated with the current sources on
3 October 2026 with the same result. The adapter rejected the session, as intended. The shipped
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
python3 deploy/auth/sessions.py
Rscript deploy/auth/provision.R
docker compose -f deploy/auth/compose.yaml build app
docker compose -f deploy/auth/compose.yaml up -d
docker network connect --alias delphyr-auth-db delphyr-auth-back delphyr-dev-postgres
```

`sessions.py` also brings a fixture created earlier up to date (sign-out ends
the provider session) and writes the gateway configuration with short
lifetimes used by the lifetime check. Rebuild the image after every change of
the packages; the processes run the installed packages, not the working tree.

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

`verify-browser.py` drives the system Chromium through the real sign-in and
asserts on the database and on the technical log of the processes. On
3 October 2026 the image was built from commit `e1cee22` and every check
passed: 27 with one application process, 30 with two and with three (the
eight further accounts were spread four and four, and three, four and one),
and the four lifetime checks; with two and three processes the export was
built in another process than the one holding the session. The lifetime
checks and the stock Shiny Server check below ran at commit `7a88a8f`, which
changes only fixture scripts. Each run is recorded with its commit in
`.local/auth/qualification.json`.

| Group | Checked |
|---|---|
| Before sign-in | A request without a session, with forged identity headers, with a forged cookie and a callback without valid state are sent to the sign-in or rejected; the internal gateway hop refuses direct requests; no application process has a published port. |
| Identity | The signed-in subject is mapped to its database account and study through the websocket; an identity header added by the signed-in browser does not switch the account; a second account without membership sees no study; a direct request to every application process with forged headers gets no session. |
| Requests of a session | An uploaded contact file is previewed; an export is built by a worker step in another container and downloaded through the session's process. |
| Rights in an open page | After a right is revoked and after the account is disabled, the next action is refused and nothing changes; a new session of the disabled account is closed with the notice for unregistered accounts. |
| Invitation | A visit without a session is sent to the sign-in (the code is in the address fragment and never part of a request); another account is refused with the uniform message; opening the link and checking the invitation create nothing; the confirmed acceptance by the invited account creates a membership with participation only; a deactivated membership ends the access. |
| Sign-out | The link leaves the application, ends the account's other open page, removes the session of the gateway and ends the one at the provider: the next visit asks for credentials. |
| Routing, with several processes | Eight further accounts each reach exactly one process, the same one on a second visit, and are spread over the processes. |
| Lifetimes, with `--lifetime` | With an identity of 20 seconds an action after 25 seconds is refused with the expiry message; a page load within the gateway session gives a new identity without the provider; after the gateway session of 60 seconds a page load is sent to the provider and signed in again without credentials. |

The probes change only the synthetic accounts and restore rights and the
active flag in `finally` blocks. To reproduce:

```sh
python3 -m venv .local/auth/venv
.local/auth/venv/bin/pip install playwright requests beautifulsoup4
.local/auth/venv/bin/python deploy/auth/verify-browser.py

# several processes: eight further accounts, three processes
python3 deploy/auth/accounts.py 8
docker compose -f deploy/auth/compose.yaml up -d --force-recreate keycloak
docker compose -f deploy/auth/compose.yaml restart proxy
python3 deploy/auth/scale.py 3
DELPHYR_LOG_LEVEL=info docker compose -f deploy/auth/compose.yaml \
  -f deploy/auth/compose.direct.yaml -f deploy/auth/compose.scale.yaml \
  --profile three up -d app app2 app3
docker exec delphyr-auth-gateway nginx -s reload
.local/auth/venv/bin/python deploy/auth/verify-browser.py

# lifetimes: one process, short lifetimes, then back
python3 deploy/auth/scale.py 1 && docker exec delphyr-auth-gateway nginx -s reload
docker compose -f deploy/auth/compose.yaml -f deploy/auth/compose.direct.yaml \
  -f deploy/auth/compose.lifetime.yaml up -d proxy app
.local/auth/venv/bin/python deploy/auth/verify-browser.py --lifetime
docker compose -f deploy/auth/compose.yaml -f deploy/auth/compose.direct.yaml up -d proxy app
```

The routing and export checks read the technical log of the processes and
therefore need the level `info`.

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

An accepted hosting path must demonstrate the same checks on its own
components: a real browser sign-in, the identity in the websocket, resistance
to forged headers, rejection without a session and on the direct port, revoked
rights, invitation acceptance, lifetimes, sign-out and, with several
processes, routing by account. Local HTTP evidence does not qualify production
TLS, the institutional account lifecycle, MFA policy, central logout by the
institution's provider, another reverse proxy, or production network and
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
