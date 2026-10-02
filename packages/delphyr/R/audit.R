# Actions performed by panel members. Their account reference is withheld from
# the audit trail so that it cannot link an account to research responses.
audit_panel_actions <- c("consent", "save", "submit", "withdraw_participation", "feedback_displayed", "feedback_download", "invitation_accept")

#' Read the audit trail of a study
#'
#' Every event names time, action, object and actor, with the recorded
#' rationale where the action required one. Staff are referenced by their
#' account UUID. Panel actions carry no account reference, and worker events
#' reference the person who approved the work.
#' @param repo Repository.
#' @param actor Actor with audit or manage capability.
#' @param study_id Study UUID.
#' @param from,to Optional inclusive time limits with an explicit offset,
#'   for example "2026-10-02T00:00:00Z".
#' @param actions Optional action codes to include.
#' @param limit Maximum number of events, newest first, from 1 to 100000.
#' @return Data frame occurred_at, action, detail, object_ref, reason,
#'   actor_kind (staff, panel or worker) and actor_ref.
#' @export
list_audit_events <- function(repo, actor, study_id, from = NULL, to = NULL, actions = NULL, limit = 500L) {
  authorize_any(repo, actor, study_id, c("audit", "manage"))
  stamp <- function(x, path) {
    if (is.null(x)) {
      return(NA_character_)
    }
    ensure(scalar_text(x) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$", x), path)
    x
  }
  from <- stamp(from, "audit.from")
  to <- stamp(to, "audit.to")
  ensure(whole(limit) && length(limit) == 1L && limit >= 1L && limit <= 100000L, "audit.limit")
  filter <- NA_character_
  if (!is.null(actions)) {
    ensure(is.character(actions) && length(actions) > 0L && length(actions) <= 100L && all(grepl("^[a-z_:]{1,80}$", actions)), "audit.actions")
    filter <- paste(unique(actions), collapse = ",")
  }
  x <- query(repo, "SELECT to_char(occurred_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') AS occurred_at,action,detail,object_ref,reason,actor_id FROM ops.audit WHERE study_id=$1 AND ($2::timestamptz IS NULL OR occurred_at>=$2::timestamptz) AND ($3::timestamptz IS NULL OR occurred_at<=$3::timestamptz) AND ($4::text IS NULL OR action=ANY(string_to_array($4,','))) ORDER BY occurred_at DESC,id LIMIT $5", study_id, from, to, filter, as.integer(limit))
  kind <- ifelse(x$action %in% audit_panel_actions, "panel", ifelse(startsWith(x$action, "message_"), "worker", "staff"))
  x$actor_kind <- kind
  x$actor_ref <- ifelse(kind == "panel", NA_character_, x$actor_id)
  x$actor_id <- NULL
  x
}
