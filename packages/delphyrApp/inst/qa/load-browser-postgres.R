# Load qualification with real browser sessions against PostgreSQL:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/load-fixture-postgres.R
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/load-browser-postgres.R
#
# Each session is a separate Chromium page with its own synthetic identity and
# its own database connection under the restricted runtime role. A script in
# the page behaves like a person: it opens the second round, rates every field
# after a short pause, waits for each confirmed save and submits. The run
# passes only if every answer confirmed in a browser is the stored answer.
#
#   DELPHYR_LOAD_SESSIONS   concurrent sessions (default 50)
#   DELPHYR_LOAD_PROCESSES  application processes sharing them (default 1)
#   DELPHYR_LOAD_THINK      pause before each rating in seconds, "min,max" (default 1,4)
#   DELPHYR_LOAD_RAMP       seconds over which the sessions arrive (default 120)
#   DELPHYR_LOAD_FIELDS     fields rated per session, 0 for all (default 0)
source("packages/delphyrApp/inst/qa/browser-helpers.R")
fixture <- readRDS(file.path(qa_root, ".local", "load-fixture.rds"))
sessions <- as.integer(Sys.getenv("DELPHYR_LOAD_SESSIONS", "50"))
processes <- as.integer(Sys.getenv("DELPHYR_LOAD_PROCESSES", "1"))
think <- as.numeric(strsplit(Sys.getenv("DELPHYR_LOAD_THINK", "1,4"), ",", fixed = TRUE)[[1]])
ramp <- as.numeric(Sys.getenv("DELPHYR_LOAD_RAMP", "120"))
limit_fields <- as.integer(Sys.getenv("DELPHYR_LOAD_FIELDS", "0"))
offset <- as.integer(Sys.getenv("DELPHYR_LOAD_OFFSET", "0"))
autosave_ms <- 1500
stopifnot(sessions >= 1L, processes >= 1L, length(think) == 2L, offset + sessions <= length(fixture$principals))
admin <- qa_admin()
tag <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
principals <- fixture$principals[offset + seq_len(sessions)]
already <- DBI::dbGetQuery(admin$con, "SELECT count(*)::int AS n FROM research.response_revisions v JOIN research.enrollments e ON e.id=v.enrollment_id JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id WHERE v.round_id=$1 AND m.principal_id = ANY($2::uuid[])", params = list(fixture$rounds[2], paste0("{", paste(principals, collapse = ","), "}")))$n
if (already > 0L) stop("These members already answered the second round; choose another DELPHYR_LOAD_OFFSET or build a new fixture.")

# The identity header stands in for a qualified gateway; test use only.
Sys.setenv(DELPHYR_LOG_LEVEL = "info")
build <- function(repo, data, connect) {
  DBI::dbDisconnect(repo$con)
  delphyrApp::run_app(repo_factory = connect, actor_factory = function(session, repo) delphyr::demo_actor(repo, session$request$HTTP_X_QA_PRINCIPAL))
}
ports <- 3900L + seq_len(processes)
hosts <- lapply(seq_len(processes), function(i) qa_host(paste0("load-", tag, "-", i), ports[i], build))
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)
logs <- file.path(qa_root, ".checks", paste0("load-", tag, "-", seq_len(processes), ".log"))
# Every application process answers before the first session arrives.
for (port in ports) {
  up <- FALSE
  for (attempt in 1:300) {
    up <- tryCatch({
      connection <- url(sprintf("http://127.0.0.1:%d", port), open = "rb")
      close(connection)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (up) break
    Sys.sleep(.2)
  }
  if (!up) stop("Application process did not start on port ", port)
}

# A page in the background must keep its timers, as a person's visible tab does.
chromote::set_chrome_args(unique(c(chromote::default_chrome_args(), "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows", "--disable-renderer-backgrounding")))
# The participant: opens the second round, rates every field with a random
# value after a pause, waits for each confirmed save and submits.
agent <- qa_participant_script(2L, answers = NULL, think = think, limit = limit_fields)

pages <- vector("list", sessions)
started <- Sys.time()
elapsed <- function() as.numeric(difftime(Sys.time(), started, units = "secs"))
samples <- list()
# Processor time of an application process since its start, in seconds.
ticks <- as.numeric(system2("getconf", "CLK_TCK", stdout = TRUE))
processor_seconds <- function(pid) {
  stat <- tryCatch(readLines(sprintf("/proc/%d/stat", pid), warn = FALSE), error = function(e) NA_character_)
  if (is.na(stat)) return(NA_real_)
  fields <- strsplit(sub("^.*\\) ", "", stat), " ", fixed = TRUE)[[1]]
  sum(as.numeric(fields[12:13])) / ticks
}
memory_mb <- function(pid) tryCatch(as.numeric(sub("^VmRSS:\\s+([0-9]+) kB$", "\\1", grep("^VmRSS:", readLines(sprintf("/proc/%d/status", pid), warn = FALSE), value = TRUE))) / 1024, error = function(e) NA_real_)
last <- list(time = Sys.time(), cpu = vapply(hosts, function(h) processor_seconds(h$get_pid()), numeric(1)))
sample <- function() {
  activity <- DBI::dbGetQuery(admin$con, "SELECT count(*) FILTER (WHERE usename='delphyr_runtime')::int AS connections, count(*) FILTER (WHERE usename='delphyr_runtime' AND state='active')::int AS active, count(*) FILTER (WHERE usename='delphyr_runtime' AND state='idle in transaction')::int AS in_transaction, count(*) FILTER (WHERE usename='delphyr_runtime' AND wait_event_type='Lock')::int AS waiting_for_lock FROM pg_stat_activity")
  now <- Sys.time()
  cpu <- vapply(hosts, function(h) processor_seconds(h$get_pid()), numeric(1))
  interval <- as.numeric(difftime(now, last$time, units = "secs"))
  # Share of one processor used by each application process since the last sample.
  busy <- if (interval > 0) 100 * (cpu - last$cpu) / interval else rep(NA_real_, length(cpu))
  last <<- list(time = now, cpu = cpu)
  phases <- vapply(pages, function(s) if (is.null(s)) "pending" else tryCatch(s$js("window.__participant ? window.__participant.phase : 'opening'"), error = function(e) "unreachable"), character(1))
  samples[[length(samples) + 1L]] <<- data.frame(
    second = round(elapsed(), 1), activity, busiest_process_percent = round(max(busy, na.rm = TRUE)), mean_process_percent = round(mean(busy, na.rm = TRUE)),
    rss_mb = round(sum(vapply(hosts, function(h) memory_mb(h$get_pid()), numeric(1)), na.rm = TRUE)),
    rating = sum(phases == "rating"), loading = sum(phases %in% c("loading", "start", "opening")), done = sum(phases == "done")
  )
}
# Sessions arrive spread over the ramp.
for (i in seq_len(sessions)) {
  while (elapsed() < (i - 1) * ramp / max(1L, sessions)) Sys.sleep(.05)
  s <- qa_session()
  s$identity(list(`X-QA-Principal` = principals[i]))
  s$b$Page$enable()
  invisible(s$b$Page$addScriptToEvaluateOnNewDocument(source = agent))
  s$b$Page$navigate(sprintf("http://127.0.0.1:%d", ports[1 + (i - 1) %% processes]), wait_ = FALSE)
  pages[[i]] <- s
  if (i %% 5L == 0L) sample()
}
cat(sprintf("%d sessions opened after %.0f s\n", sessions, elapsed()))
repeat {
  Sys.sleep(5)
  sample()
  latest <- samples[[length(samples)]]
  cat(sprintf("t=%5.0fs  loading=%2d  rating=%2d  done=%2d  busiest process=%3.0f%%  mean=%3.0f%%  memory=%5d MB  db active=%d waiting=%d\n", latest$second, latest$loading, latest$rating, latest$done, latest$busiest_process_percent, latest$mean_process_percent, latest$rss_mb, latest$active, latest$waiting_for_lock))
  finished <- vapply(pages, function(s) isTRUE(tryCatch(s$js("!!(window.__participant && window.__participant.done)"), error = function(e) FALSE)), logical(1))
  if (all(finished) || elapsed() > as.numeric(Sys.getenv("DELPHYR_LOAD_TIMEOUT", "7200"))) break
}
results <- lapply(pages, function(s) tryCatch(jsonlite::fromJSON(s$js("JSON.stringify(window.__participant || {phase:'missing', saves:[], errors:['no agent'], done:false})"), simplifyVector = FALSE), error = function(e) list(phase = "unreachable", saves = list(), errors = list(conditionMessage(e)), done = FALSE)))
output_errors <- vapply(pages, function(s) tryCatch(s$output_errors(), error = function(e) NA_integer_), integer(1))
for (s in pages) try(s$close(), silent = TRUE)
duration <- elapsed()

# Every answer a browser saw confirmed must be the stored answer.
lost <- 0L
confirmed <- 0L
submitted <- 0L
for (i in seq_len(sessions)) {
  actor <- demo_actor(admin, principals[i])
  enrollment <- list_enrollments(admin, actor, fixture$study_id)
  enrollment <- enrollment$id[enrollment$number == 2L]
  q <- get_questionnaire(admin, actor, enrollment)
  for (save in results[[i]]$saves) {
    if (!identical(save$state, "saved")) next
    confirmed <- confirmed + 1L
    stored <- q$responses$value_int[match(q$items$id[save$row], q$responses$round_item_id)]
    if (is.na(stored) || stored != as.integer(save$value)) lost <- lost + 1L
  }
  if (!is.null(results[[i]]$submit_ms)) {
    if (nrow(q$receipt) == 1L) submitted <- submitted + 1L else lost <- lost + 1L
  }
}
quantiles <- function(x) if (length(x)) as.list(round(stats::quantile(x, c(.5, .95, .99), names = FALSE))) else list(NA, NA, NA)
named <- function(x) stats::setNames(x, c("p50", "p95", "p99"))
save_ms <- unlist(lapply(results, function(r) vapply(Filter(function(s) identical(s$state, "saved"), r$saves), function(s) s$ms, numeric(1))))
entries <- unlist(lapply(logs, function(path) Filter(Negate(is.null), lapply(readLines(path, warn = FALSE), function(line) if (startsWith(line, "{")) jsonlite::fromJSON(line)))), recursive = FALSE)
service <- function(operation) vapply(Filter(function(x) identical(x$operation, operation) && identical(x$outcome, "ok"), entries), function(x) x$duration_ms, numeric(1))
not_ok <- Filter(function(x) !identical(x$outcome, "ok"), entries)
usage <- do.call(rbind, samples)
errors <- unlist(lapply(results, function(r) unlist(r$errors)))
result <- list(
  status = NA_character_, run = tag, commit = tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_),
  scope = "real Chromium sessions, Shiny application processes and PostgreSQL on one machine over loopback; excludes TLS, the authentication gateway and wide-area latency",
  environment = list(r = R.version.string, shiny = as.character(utils::packageVersion("shiny")), postgres = DBI::dbGetQuery(admin$con, "SHOW server_version")$server_version, cores = parallel::detectCores(), memory_gb = round(as.numeric(strsplit(trimws(system2("awk", c("'/MemTotal/ {print $2}'", "/proc/meminfo"), stdout = TRUE)), " ")[[1]][1]) / 1024^2)),
  study = fixture[c("code", "members", "items", "fields")],
  database_rows = as.list(DBI::dbGetQuery(admin$con, "SELECT (SELECT count(*) FROM research.response_revisions)::int AS response_revisions,(SELECT count(*) FROM ops.audit)::int AS audit_events,(SELECT count(*) FROM ops.commands)::int AS command_receipts")),
  sessions = sessions, processes = processes, think_seconds = think, ramp_seconds = ramp, autosave_pause_ms = autosave_ms, duration_seconds = round(duration),
  sessions_completed = sum(vapply(results, function(r) isTRUE(r$done) && identical(r$phase, "done"), logical(1))),
  first_block_ready_ms = named(quantiles(unlist(lapply(results, function(r) r$ready_ms)))),
  next_block_ready_ms = named(quantiles(unlist(lapply(results, function(r) unlist(r$blocks))))),
  saves_confirmed = confirmed,
  # From the entry in the browser to the confirmation shown, including the deliberate pause.
  save_confirmation_ms = named(quantiles(save_ms)),
  save_after_pause_ms = named(quantiles(pmax(0, save_ms - autosave_ms))),
  save_service_ms = named(quantiles(service("save_response"))),
  submissions_confirmed = submitted, submit_confirmation_ms = named(quantiles(unlist(lapply(results, function(r) r$submit_ms)))), submit_service_ms = named(quantiles(service("submit_round"))),
  questionnaire_service_ms = named(quantiles(service("get_questionnaire"))), feedback_service_ms = named(quantiles(service("get_feedback"))),
  refused_or_failed_operations = length(not_ok), browser_errors = length(errors), output_errors = sum(output_errors, na.rm = TRUE), lost_confirmed_writes = lost,
  application_processes = list(
    busiest_process_percent_peak = max(usage$busiest_process_percent, na.rm = TRUE), mean_process_percent_while_rating = round(mean(usage$mean_process_percent[usage$rating > 0], na.rm = TRUE)),
    busiest_process_percent_while_rating = round(mean(usage$busiest_process_percent[usage$rating > 0], na.rm = TRUE)), memory_mb_peak = max(usage$rss_mb, na.rm = TRUE)
  ),
  database = list(connections_peak = max(usage$connections), active_peak = max(usage$active), waiting_for_lock_peak = max(usage$waiting_for_lock), in_transaction_peak = max(usage$in_transaction))
)
target <- 2000
complete <- result$sessions_completed == sessions && lost == 0L && length(errors) == 0L && length(not_ok) == 0L && confirmed == sessions * (if (limit_fields > 0L) limit_fields else fixture$fields)
result$status <- if (!complete) "FAIL" else if (result$save_after_pause_ms$p95 < target) "PASS" else "TARGET_MISSED"
result$target <- "p95 of a confirmed save after the pause below 2000 ms; no lost confirmed write"
jsonlite::write_json(result, file.path(qa_root, ".checks", paste0("load-browser-", tag, ".json")), auto_unbox = TRUE, pretty = TRUE, null = "null")
utils::write.csv(usage, file.path(qa_root, ".checks", paste0("load-browser-", tag, "-samples.csv")), row.names = FALSE)
if (length(errors)) print(utils::head(table(errors), 20))
if (length(not_ok)) print(utils::head(table(vapply(not_ok, function(x) paste(x$operation, x$outcome, x$error_class), character(1))), 20))
DBI::dbDisconnect(admin$con)
str(result, max.level = 2)
if (!complete) stop("The load run did not complete without errors.")
