#' Rights of the signed-in account outside any study
#' @param repo Repository.
#' @param actor Server actor.
#' @return List with can_create_study. Creating a study is granted by the
#'   operator to an account, never chosen in the interface.
#' @export
get_account_rights <- function(repo, actor) {
  p <- identity_check(repo, actor)
  list(can_create_study = isTRUE(p$can_create))
}
#' List study staff and their current rights
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @return One row per staff account: principal UUID, issuer, subject, whether
#'   the account and membership are active, and granted and revoked rights.
#'   Panel membership is not part of this list.
#' @export
list_study_staff <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "manage")
  x <- query(repo, "SELECT m.principal_id,p.issuer,p.subject,(m.active AND p.active) AS active,c.capability,(c.revoked_at IS NULL) AS granted FROM identity.memberships m JOIN identity.principals p ON p.id=m.principal_id JOIN identity.capabilities c ON c.study_id=m.study_id AND c.membership_id=m.id WHERE m.study_id=$1 AND c.capability<>'panel' ORDER BY p.issuer,p.subject,c.capability", study_id)
  staff <- unique(x[, c("principal_id", "issuer", "subject", "active"), drop = FALSE])
  rights <- function(id, granted) paste(x$capability[x$principal_id == id & x$granted == granted], collapse = ", ")
  staff$granted <- vapply(staff$principal_id, rights, character(1), granted = TRUE, USE.NAMES = FALSE)
  staff$revoked <- vapply(staff$principal_id, rights, character(1), granted = FALSE, USE.NAMES = FALSE)
  rownames(staff) <- NULL
  staff
}
#' Resolve or register a staff account by its stable identity
#'
#' Rights are granted to an exact issuer and subject, never to an email
#' address. An account of a verified gateway issuer (an http or https URL) is
#' registered if it does not exist yet; any other issuer, such as synthetic
#' development accounts, must already be provisioned. The account receives no
#' right by this step. A disabled account is not reactivated.
#' @inheritParams list_study_staff
#' @param issuer Exact issuer of the account.
#' @param subject Stable subject of the account.
#' @param reason Why this account is to receive rights.
#' @param command_id Idempotency key.
#' @return Principal UUID for set_capability().
#' @export
register_staff_account <- function(repo, actor, study_id, issuer, subject, reason, command_id) {
  ensure(scalar_text(issuer) && nchar(issuer, type = "bytes") <= 512L && !grepl("[[:space:][:cntrl:]]", issuer), "staff.issuer")
  ensure(scalar_text(subject) && nchar(subject, type = "bytes") <= 1024L && !grepl("[[:space:],[:cntrl:]]", subject), "staff.subject")
  ensure(scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "staff.reason")
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    command(repo, actor, study_id, "staff_account", command_id, list(issuer, subject, reason), function() {
      p <- if (grepl("^https?://[^[:space:]?#@]+$", issuer)) {
        query(repo, "INSERT INTO identity.principals(id,issuer,subject) VALUES($1,$2,$3) ON CONFLICT(issuer,subject) DO UPDATE SET subject=EXCLUDED.subject RETURNING id,active", uid(), issuer, subject)
      } else {
        query(repo, "SELECT id,active FROM identity.principals WHERE issuer=$1 AND subject=$2", issuer, subject)
      }
      ensure(nrow(p) == 1L, "staff.account", "DEL_NOT_FOUND")
      ensure(isTRUE(p$active), "staff.account_disabled", "DEL_FORBIDDEN")
      list(id = p$id)
    }, reason = reason)
  })
}
#' List the panel of a study by pseudonym
#' @inheritParams list_study_staff
#' @return Study pseudonym, stakeholder group, whether the member is active or
#'   withdrew, and counts of rounds enrolled and submitted. No account
#'   references, contacts or responses.
#' @export
list_panel <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "manage")
  query(repo, "SELECT p.id AS panelist_id,p.group_code,p.active,(w.id IS NOT NULL) AS withdrawn,
      (SELECT count(*) FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id WHERE e.study_id=p.study_id AND e.panelist_id=p.id AND r.state<>'cancelled')::int AS rounds_enrolled,
      (SELECT count(*) FROM research.submissions s JOIN research.enrollments e ON e.id=s.enrollment_id WHERE e.study_id=p.study_id AND e.panelist_id=p.id)::int AS rounds_submitted
    FROM research.panelists p LEFT JOIN research.participation_withdrawals w ON w.study_id=p.study_id AND w.panelist_id=p.id WHERE p.study_id=$1 ORDER BY p.group_code,p.id", study_id)
}
#' List the human item decisions of a study
#' @inheritParams list_study_staff
#' @param actor Actor with manage or analyse capability.
#' @return Round number, item, disposition, rationale and time of each decision.
#' @export
list_item_decisions <- function(repo, actor, study_id) {
  authorize_any(repo, actor, study_id, c("manage", "analyse"))
  query(repo, "SELECT r.number AS round_number,d.item_code,d.disposition,d.reason,(SELECT min(au.occurred_at)::text FROM ops.audit au WHERE au.study_id=d.study_id AND au.action='decision' AND au.object_ref=d.id::text) AS decided_at FROM research.decisions d JOIN research.analyses a ON a.study_id=d.study_id AND a.id=d.analysis_id JOIN research.snapshots s ON s.study_id=a.study_id AND s.id=a.snapshot_id JOIN research.rounds r ON r.id=s.round_id WHERE d.study_id=$1 ORDER BY r.number,d.item_code,decided_at,d.id", study_id)
}
