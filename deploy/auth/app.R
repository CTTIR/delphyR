# No browser-supplied user, issuer, role or principal is accepted here.
gateway_secret <- readChar('/run/delphyr-auth/gateway.secret', nchars=256L)
config <- delphyr::new_authentication_config(
  issuer='http://127.0.0.1:4190/realms/delphyr',
  gateway_secret=gateway_secret,
  trusted_proxy_addresses=strsplit(Sys.getenv('DELPHYR_AUTH_PEERS','127.0.0.1,::1'),',',fixed=TRUE)[[1]],
  max_session_seconds=900L)
delphyrApp::run_app(
  repo_factory=function() delphyr::connect_repository(
    host='delphyr-auth-db',port=5432,dbname='delphyr',user='delphyr_runtime',
    environment='development',artifact_root='/tmp/delphyr-auth-artifacts'),
  actor_factory=function(session,repo) tryCatch(
    delphyr::authenticated_actor(repo,session$request,config),
    delphyr_error=function(e) {
      message("Gateway admission rejected: ",e$path,
        "; transport peer: ",session$request$REMOTE_ADDR,
        "; subject header present: ",!is.null(session$request$HTTP_X_FORWARDED_USER),
        "; gateway header present: ",!is.null(session$request$HTTP_X_DELPHYR_GATEWAY))
      stop(e)
    }))
