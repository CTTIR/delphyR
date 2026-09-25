#' Configure the trusted authentication gateway boundary
#' @param issuer Exact OIDC issuer configured in the independently validating proxy.
#' @param gateway_secret Private random secret overwritten by the internal gateway.
#' @param trusted_proxy_addresses Exact transport peer addresses observed by httpuv.
#' @param max_session_seconds Maximum lifetime of one Shiny actor, at most one hour.
#' @return Server-only delphyr_authentication_config. Never serialize to a browser.
#' @export
new_authentication_config <- function(issuer, gateway_secret, trusted_proxy_addresses,
                                      max_session_seconds = 900L) {
  ensure(scalar_text(issuer) && grepl("^https?://[^[:space:]?#@]+$", issuer), "authentication.issuer")
  ensure(scalar_text(gateway_secret) && nchar(gateway_secret, type = "bytes") >= 32L &&
    nchar(gateway_secret, type = "bytes") <= 512L && !grepl("[[:space:]]", gateway_secret), "authentication.gateway_secret")
  ensure(is.character(trusted_proxy_addresses) && length(trusted_proxy_addresses) > 0 &&
    !anyNA(trusted_proxy_addresses) && all(nzchar(trusted_proxy_addresses)) &&
    !anyDuplicated(trusted_proxy_addresses), "authentication.peers")
  ensure(whole(max_session_seconds) && length(max_session_seconds) == 1L &&
    max_session_seconds >= 1L && max_session_seconds <= 3600L, "authentication.lifetime")
  structure(
    list(
      issuer = issuer, gateway_secret = gateway_secret,
      trusted_proxy_addresses = trusted_proxy_addresses, max_session_seconds = max_session_seconds
    ),
    class = "delphyr_authentication_config"
  )
}
#' Resolve a verified gateway subject to a current database principal
#'
#' This adapter does not implement OIDC or verify browser credentials. It accepts
#' only the transport and headers established by the separately configured,
#' isolated authentication gateway. A header alone is not authentication.
#' @param repo Repository.
#' @param request Shiny session$request received on the server, never browser input.
#' @param config Server-only output of new_authentication_config().
#' @return Short-lived delphyr_actor. Unknown, disabled, spoofed or missing
#'   identities fail closed with DEL_UNAUTHORIZED. No account is auto-provisioned.
#' @export
#' @examples
#' if (FALSE) {
#'   config <- new_authentication_config(
#'     "https://identity.example/realms/study",
#'     Sys.getenv("DELPHYR_GATEWAY_SECRET"), "127.0.0.1"
#'   )
#'   # In a trusted session factory: authenticated_actor(repo, session$request, config)
#' }
authenticated_actor <- function(repo, request, config) {
  ensure(inherits(config, "delphyr_authentication_config"), "authentication.config")
  config <- do.call(new_authentication_config, unclass(config))
  ensure(is.list(request) || is.environment(request), "authentication.request", "DEL_UNAUTHORIZED")
  peer <- request[["REMOTE_ADDR"]]
  secret <- request[["HTTP_X_DELPHYR_GATEWAY"]]
  subject <- request[["HTTP_X_FORWARDED_USER"]]
  ensure(
    scalar_text(peer) && peer %in% config$trusted_proxy_addresses,
    "authentication.peer", "DEL_UNAUTHORIZED"
  )
  ensure(
    scalar_text(secret) && nchar(secret, type = "bytes") <= 512L &&
      identical(
        digest::digest(secret, algo = "sha256", serialize = FALSE),
        digest::digest(config$gateway_secret, algo = "sha256", serialize = FALSE)
      ),
    "authentication.gateway", "DEL_UNAUTHORIZED"
  )
  ensure(scalar_text(subject) && nchar(subject, type = "bytes") <= 1024L &&
    !grepl("[[:space:],[:cntrl:]]", subject), "authentication.subject", "DEL_UNAUTHORIZED")
  p <- query(
    repo, "SELECT id FROM identity.principals WHERE issuer=$1 AND subject=$2 AND active",
    config$issuer, subject
  )
  ensure(nrow(p) == 1L, "authentication.principal", "DEL_UNAUTHORIZED")
  structure(list(
    principal_id = p$id, expires_at = Sys.time() + config$max_session_seconds,
    issuer = config$issuer
  ), class = "delphyr_actor")
}
#' @export
print.delphyr_authentication_config <- function(x, ...) {
  safe <- unclass(x)
  safe$gateway_secret <- "<redacted>"
  print(safe, ...)
  invisible(x)
}
