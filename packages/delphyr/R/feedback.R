#' Prepare disclosure-controlled feedback
#' @param analysis A delphyr_analysis.
#' @param qualitative List of reviewed summaries, each with text, reviewed and source_ref.
#' @param policy List group_statistics, minimum_display_cell_n, complementary_suppression.
#' @return delphyr_feedback_draft. Suppressed data are removed, not hidden in markup.
#' @export
#' @examples
#' prepare_feedback(analyse_round(demo_snapshot()))$hash
prepare_feedback <- function(analysis,qualitative=list(),policy=list(group_statistics=FALSE,minimum_display_cell_n=5L,complementary_suppression=TRUE)) {
  ensure(inherits(analysis,"delphyr_analysis"),"analysis")
  known_keys(policy,c("group_statistics","minimum_display_cell_n","complementary_suppression"),"policy")
  ensure(whole(policy$minimum_display_cell_n)&&length(policy$minimum_display_cell_n)==1&&policy$minimum_display_cell_n>0,"policy.minimum_display_cell_n")
  ensure(isTRUE(policy$complementary_suppression)&&is.logical(policy$group_statistics)&&length(policy$group_statistics)==1,"policy")
  for(q in qualitative) {
    known_keys(q,c("text","reviewed","source_ref"),"qualitative")
    ensure(isTRUE(q$reviewed)&&scalar_text(q$text)&&scalar_text(q$source_ref),"qualitative.review")
  }
  r<-analysis$results; d<-analysis$distributions
  # All-or-nothing suppression within an item prevents total-minus-subgroup reconstruction.
  if(!policy$group_statistics) {r<-r[r$stratum=="overall",,drop=FALSE]; if(nrow(d))d<-d[d$stratum=="overall",,drop=FALSE]}
  key<-function(z)paste(z$item_code,z$item_version,z$dimension_code,sep="\034")
  bad<-unique(key(r[r$n_valid<policy$minimum_display_cell_n,,drop=FALSE]))
  r$suppressed<-key(r)%in%bad
  numeric_cols<-names(r)[vapply(r,is.numeric,logical(1))]
  numeric_cols<-setdiff(numeric_cols,c("round_number","item_version"))
  r[r$suppressed,numeric_cols]<-NA
  r$classification[r$suppressed]<-NA_character_
  if(nrow(d)) d<-d[!key(d)%in%bad,,drop=FALSE]
  x<-list(results=r,distributions=d,qualitative=qualitative,policy=policy,analysis_hash=analysis$provenance$result_hash)
  x$hash<-content_hash(x)
  structure(x,class="delphyr_feedback_draft")
}
#' Validate a feedback draft and its immutable hash
#' @param draft Output of prepare_feedback().
#' @return TRUE or DEL_VALIDATION.
#' @export
#' @examples
#' validate_feedback(prepare_feedback(analyse_round(demo_snapshot())))
validate_feedback <- function(draft) {
  ensure(inherits(draft,"delphyr_feedback_draft"),"feedback")
  x<-unclass(draft); h<-x$hash; x$hash<-NULL
  ensure(identical(h,content_hash(x)),"feedback.hash")
  TRUE
}
