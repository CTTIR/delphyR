#' Construct a validated response scale
#' @param type One of ordinal_integer, binary, free_text.
#' @param levels Ordered integer categories; empty for text.
#' @param labels Category labels, one per level.
#' @param missing_options Allowed explicit missing categories.
#' @return A delphyr_scale. Invalid input raises DEL_VALIDATION.
#' @export
#' @examples
#' new_scale("ordinal_integer", 1:9, as.character(1:9))
new_scale <- function(type, levels = integer(), labels = as.character(levels),
                      missing_options = c("unable_to_judge", "abstained")) {
  ensure(length(type) == 1L && type %in% c("ordinal_integer", "binary", "free_text"), "scale.type")
  ensure(is.character(missing_options) && !anyDuplicated(missing_options) &&
    all(missing_options %in% c("unable_to_judge", "abstained", "not_applicable")), "scale.missing_options")
  if (type == "free_text") ensure(length(levels) == 0L, "scale.levels") else {
    ensure(whole(levels) && length(levels) >= 2L && !anyDuplicated(levels) &&
      all(diff(levels) > 0), "scale.levels")
    if (type == "binary") ensure(identical(as.integer(levels), 0:1), "scale.binary")
    ensure(is.character(labels) && length(labels) == length(levels) &&
      all(!is.na(labels) & nzchar(labels)), "scale.labels")
  }
  structure(list(type = type, levels = as.integer(levels), labels = labels,
    missing_options = missing_options), class = "delphyr_scale")
}
#' Validate and normalize an answer
#' @param value Scalar integer or text, or NULL for missing responses.
#' @param status Answer status.
#' @param scale A scale created by new_scale().
#' @return List with status, value_int and value_text; DEL_VALIDATION on error.
#' @export
#' @examples
#' validate_response(7, "answered", new_scale("ordinal_integer", 1:9))
validate_response <- function(value, status, scale) {
  ensure(inherits(scale, "delphyr_scale"), "scale")
  ensure(length(status) == 1L && status %in% c("answered", "not_answered", scale$missing_options), "status")
  empty <- is.null(value) || (length(value) == 1L && is.na(value))
  if (status != "answered") {
    ensure(empty, "missing.value")
    return(list(status = status, value_int = NA_integer_, value_text = NA_character_))
  }
  if (scale$type == "free_text") {
    ensure(scalar_text(value) && nchar(value, type = "bytes") <= 20000L, "value_text")
    list(status = status, value_int = NA_integer_, value_text = enc2utf8(value))
  } else {
    ensure(whole(value) && length(value) == 1L && value %in% scale$levels, "value_int")
    list(status = status, value_int = as.integer(value), value_text = NA_character_)
  }
}
validate_rule <- function(rule, scale = NULL) {
  known_keys(rule, c("agree_values", "disagree_values", "min_valid_n", "in", "out", "group_policy"), "consensus")
  a <- unlist(rule$agree_values); d <- unlist(rule$disagree_values)
  ensure(whole(a) && whole(d) && !anyDuplicated(a) && !anyDuplicated(d) && !length(intersect(a,d)), "consensus.categories")
  if (!is.null(scale)) ensure(all(c(a,d) %in% scale$levels), "consensus.scale")
  ensure(whole(rule$min_valid_n) && length(rule$min_valid_n) == 1L && rule$min_valid_n > 0, "consensus.min_valid_n")
  for (side in c("in", "out")) {
    known_keys(rule[[side]], c("agree", "disagree"), paste0("consensus.",side))
    for (v in c("agree", "disagree")) {
      b <- rule[[side]][[v]]
      known_keys(b, c("operator", "proportion"), "consensus.bound")
      ensure(b$operator %in% c("gte", "gt", "lte", "lt") && length(b$operator) == 1L,
        "consensus.operator")
      ensure(is.numeric(b$proportion) && length(b$proportion) == 1L &&
        is.finite(b$proportion) && b$proportion >= 0 && b$proportion <= 1, "consensus.proportion")
    }
  }
  # Detect overlap on the feasible probability triangle, including strict boundaries.
  b <- sort(unique(c(0,1,unlist(lapply(rule[c("in","out")],function(z) vapply(z, `[[`, numeric(1), "proportion"))))))
  candidates <- sort(unique(c(b, (head(b,-1)+tail(b,-1))/2)))
  overlap <- any(vapply(candidates, function(a) any(vapply(candidates, function(d)
    a+d <= 1 && rule_matches(a,d,rule$`in`) && rule_matches(a,d,rule$out), logical(1))), logical(1)))
  ensure(!overlap, "consensus.overlap")
  ensure(length(rule$group_policy) == 1 && rule$group_policy %in% c("pooled", "all_required_groups"), "consensus.group_policy")
  invisible(TRUE)
}
bound_matches <- function(x, b) switch(b$operator, gte=x>=b$proportion, gt=x>b$proportion,
  lte=x<=b$proportion, lt=x<b$proportion)
rule_matches <- function(a,d,r) bound_matches(a,r$agree) && bound_matches(d,r$disagree)

#' Synthetic protocol example
#' @return Complete demo configuration; thresholds are examples, not recommendations.
#' @export
#' @examples
#' validate_protocol(demo_protocol())$valid
demo_protocol <- function() {
  b <- function(op,p) list(operator=op,proportion=p)
  list(schema_version="1.0", study=list(code="DEMO-001", title="Synthetische Delphi-Studie",
    environment="demo", timezone="Europe/Berlin", languages=c("de","en"), default_language="de",
    design="modified_round_based_delphi", rationale="Synthetische Demonstration"),
    panel=list(eligibility_policy="invited_only",late_entry=FALSE,return_after_missed_round=FALSE,
      groups=c("professionals","public_contributors")),
    instrument=list(dimensions=list(list(code="relevance",scale="relevance_9")),
      scales=list(relevance_9=list(type="ordinal_integer",values=1:9,
        anchors=list(low="nicht relevant",high="aeusserst relevant"),missing_options=c("unable_to_judge","abstained"))),
      randomize_items=FALSE,require_explicit_answer=TRUE,editing_after_submission=FALSE),
    analysis=list(primary_population="submitted_only",denominator="valid_ratings",quantile_type=7,
      consensus=list(agree_values=7:9,disagree_values=1:3,min_valid_n=10,
        `in`=list(agree=b("gte",.7),disagree=b("lt",.15)),out=list(agree=b("lt",.15),disagree=b("gte",.7)),
        group_policy="all_required_groups"),
      stability=list(enabled=TRUE,comparable_versions_only=TRUE,
        metrics=c("median_absolute_change","proportion_unchanged"),decision_threshold=NULL)),
    feedback=list(own_previous_rating=TRUE,distribution=TRUE,median=TRUE,iqr=TRUE,valid_n=TRUE,
      group_statistics=FALSE,minimum_display_cell_n=5,complementary_suppression=TRUE,
      comments="moderated_summary",live_current_round_results=FALSE),
    communications=list(mode="sink",campaign_approval_required=TRUE,automated_reminders_enabled=FALSE),
    stopping=list(max_rounds=3,allow_persistent_dissensus=TRUE,automatic_study_completion=FALSE))
}
config_scales <- function(p) lapply(p$instrument$scales,function(s)
  new_scale(s$type,unlist(s$values),missing_options=unlist(s$missing_options)))
check_protocol <- function(p) {
  template <- demo_protocol()
  known_keys(p,names(template),"protocol")
  ensure(identical(p$schema_version,"1.0"),"schema_version")
  for (k in setdiff(names(template), "schema_version")) known_keys(p[[k]],names(template[[k]]),k)
  for (k in c("code","title","rationale")) ensure(scalar_text(p$study[[k]]),paste0("study.",k))
  ensure(p$study$environment %in% c("demo","production"),"study.environment")
  # Production approval deliberately requires a separately implemented governance contract.
  ensure(p$study$environment == "demo", "production_governance_not_approved")
  ensure(p$study$timezone %in% OlsonNames(),"study.timezone")
  ensure(all(unlist(p$study$languages) %in% c("de","en")) &&
    p$study$default_language %in% unlist(p$study$languages),"study.languages")
  ensure(p$study$design %in% c("modified_round_based_delphi","exploratory_round_based_delphi"),"study.design")
  ensure(p$panel$eligibility_policy == "invited_only", "panel.eligibility_policy")
  groups <- unlist(p$panel$groups)
  ensure(is.character(groups) && length(groups)>0 && all(nzchar(groups)) && !anyDuplicated(groups),"panel.groups")
  for (k in c("late_entry","return_after_missed_round")) ensure(is.logical(p$panel[[k]]) && length(p$panel[[k]])==1 && !is.na(p$panel[[k]]),paste0("panel.",k))
  for (k in c("randomize_items","require_explicit_answer","editing_after_submission"))
    ensure(is.logical(p$instrument[[k]]) && length(p$instrument[[k]])==1 && !is.na(p$instrument[[k]]),paste0("instrument.",k))
  ensure(!p$instrument$editing_after_submission,"instrument.editing_after_submission")
  ensure(!p$instrument$randomize_items,"instrument.randomize_items_unsupported")
  ensure(length(p$instrument$scales)>0 && !is.null(names(p$instrument$scales)),"instrument.scales")
  for (s in p$instrument$scales) {
    known_keys(s,c("type","values","anchors","missing_options"),"scale")
    known_keys(s$anchors,c("low","high"),"scale.anchors")
    ensure(scalar_text(s$anchors$low) && scalar_text(s$anchors$high),"scale.anchors")
  }
  scales <- config_scales(p)
  ensure(length(p$instrument$dimensions)>0,"instrument.dimensions")
  codes <- character()
  for (d in p$instrument$dimensions) {
    known_keys(d,c("code","scale"),"dimension")
    ensure(scalar_text(d$code) && d$scale %in% names(scales),"dimension")
    codes <- c(codes,d$code)
    if(scales[[d$scale]]$type != "free_text") validate_rule(p$analysis$consensus,scales[[d$scale]])
  }
  ensure(!anyDuplicated(codes),"dimension.duplicate")
  ensure(p$analysis$primary_population=="submitted_only" && p$analysis$denominator=="valid_ratings" &&
    p$analysis$quantile_type==7,"analysis.profile")
  known_keys(p$analysis$stability,names(template$analysis$stability),"analysis.stability")
  ensure(is.null(p$analysis$stability$decision_threshold),"stability.decision_threshold")
  ensure(isTRUE(p$analysis$stability$comparable_versions_only),"stability.comparability")
  ensure(all(unlist(p$analysis$stability$metrics) %in% c("median_absolute_change","proportion_unchanged")),"stability.metrics")
  for (k in c("own_previous_rating","distribution","median","iqr","valid_n","group_statistics","complementary_suppression","live_current_round_results"))
    ensure(is.logical(p$feedback[[k]]) && length(p$feedback[[k]])==1 && !is.na(p$feedback[[k]]),paste0("feedback.",k))
  ensure(!p$feedback$live_current_round_results && p$feedback$complementary_suppression,"feedback.policy")
  ensure(whole(p$feedback$minimum_display_cell_n) && length(p$feedback$minimum_display_cell_n)==1 && p$feedback$minimum_display_cell_n>0,"feedback.minimum_display_cell_n")
  ensure(p$feedback$comments=="moderated_summary","feedback.comments")
  ensure(p$communications$mode=="sink" && isTRUE(p$communications$campaign_approval_required) && identical(p$communications$automated_reminders_enabled,FALSE),"communications")
  ensure(whole(p$stopping$max_rounds) && length(p$stopping$max_rounds)==1 && p$stopping$max_rounds>0,"stopping.max_rounds")
  ensure(isTRUE(p$stopping$allow_persistent_dissensus) && identical(p$stopping$automatic_study_completion,FALSE),"stopping")
  invisible(TRUE)
}
#' Validate a declarative study protocol
#' @param protocol Configuration list.
#' @return delphyr_validation with valid, issues, and schema_version.
#' @export
#' @examples
#' validate_protocol(demo_protocol())
validate_protocol <- function(protocol) {
  issues <- data.frame(severity=character(),code=character(),path=character(),message_key=character(),details=character())
  tryCatch(check_protocol(protocol), error=function(e) {
    path <- if(inherits(e,"delphyr_error")) e$path else "protocol.structure"
    issues <<- data.frame(severity="error",code="DEL_VALIDATION",path=path,message_key="validation.invalid",details="")
  })
  structure(list(valid=nrow(issues)==0,issues=issues,schema_version="1.0"),class="delphyr_validation")
}
#' Construct a protocol
#' @param config Complete declarative configuration.
#' @return delphyr_protocol; invalid inputs raise DEL_VALIDATION.
#' @export
#' @examples
#' new_protocol(demo_protocol())$schema_version
new_protocol <- function(config) {
  v <- validate_protocol(config)
  if(!v$valid) del_abort("DEL_VALIDATION",v$issues$path[1])
  structure(config,class=c("delphyr_protocol","list"))
}
