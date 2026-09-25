#' Classify consensus from explicit counts
#' @param counts Named list n_valid, n_agree, n_disagree.
#' @param rule Validated consensus rule.
#' @return Classification and unrounded proportions with numerator and denominator.
#' @export
#' @examples
#' classify_consensus(list(n_valid=10,n_agree=7,n_disagree=1), demo_protocol()$analysis$consensus)
classify_consensus <- function(counts, rule) {
  validate_rule(rule)
  known_keys(counts,c("n_valid","n_agree","n_disagree"),"counts")
  n <- counts$n_valid; a <- counts$n_agree; d <- counts$n_disagree
  ensure(all(vapply(counts,function(x) whole(x)&&length(x)==1&&x>=0,logical(1))) && a+d<=n,"counts")
  pa <- if(n>0) a/n else NA_real_; pd <- if(n>0) d/n else NA_real_
  status <- if(n<rule$min_valid_n) "insufficient_data" else if(rule_matches(pa,pd,rule$`in`))
    "consensus_in" else if(rule_matches(pa,pd,rule$out)) "consensus_out" else "no_consensus"
  c(counts,list(p_agree=pa,p_disagree=pd,classification=status))
}
#' Construct an immutable analysis input
#' @param responses Long data frame: panelist_id, item_code, item_version,
#'   dimension_code, answer_status, value_integer, value_text. Only submitted data.
#' @param assignments All assigned panelists: panelist_id, group_code, submitted.
#' @param items Instrument table: item_code, item_version, dimension_code, scale_code.
#' @param protocol Validated protocol.
#' @param round_number Positive round number.
#' @param snapshot_id Stable identifier, or content hash when NULL.
#' @return delphyr_snapshot, with all assigned fields materialized, including missingness.
#' @export
#' @examples
#' s <- demo_snapshot()
#' s$content_hash
new_snapshot <- function(responses, assignments, items, protocol, round_number=1L, snapshot_id=NULL) {
  protocol <- new_protocol(protocol)
  ensure(is.data.frame(assignments)&&all(c("panelist_id","group_code","submitted") %in% names(assignments)),"assignments")
  ensure(is.logical(assignments$submitted)&&!anyNA(assignments)&&!anyDuplicated(assignments$panelist_id)&&
    all(assignments$group_code %in% unlist(protocol$panel$groups)),"assignments")
  ensure(is.data.frame(items)&&all(c("item_code","item_version","dimension_code","scale_code") %in% names(items))&&nrow(items)>0&&!anyNA(items),"items")
  key <- function(d) paste(d$item_code,d$item_version,d$dimension_code,sep="\034")
  ensure(!anyDuplicated(key(items))&&whole(items$item_version)&&all(items$item_version>0),"items.keys")
  dims <- setNames(vapply(protocol$instrument$dimensions,`[[`,character(1),"scale"),vapply(protocol$instrument$dimensions,`[[`,character(1),"code"))
  ensure(all(items$dimension_code %in% names(dims))&&all(items$scale_code==dims[items$dimension_code]),"items.dimension_scale")
  required <- c("panelist_id","item_code","item_version","dimension_code","answer_status","value_integer","value_text")
  ensure(is.data.frame(responses)&&all(required %in% names(responses)),"responses")
  ensure(!anyDuplicated(paste(responses$panelist_id,key(responses))),"responses.duplicate")
  ensure(all(responses$panelist_id %in% assignments$panelist_id)&&all(key(responses)%in%key(items)),"responses.assignment")
  ensure(all(assignments$submitted[match(responses$panelist_id,assignments$panelist_id)]),"responses.unsubmitted")
  grid <- merge(assignments,items,by=NULL,sort=FALSE)
  joined <- merge(grid,responses[,required],by=c("panelist_id","item_code","item_version","dimension_code"),all.x=TRUE,sort=TRUE)
  joined$answer_status[is.na(joined$answer_status)] <- "not_answered"
  scales <- config_scales(protocol)
  for(i in seq_len(nrow(joined))) {
    sc <- scales[[joined$scale_code[i]]]
    value <- if(sc$type=="free_text") joined$value_text[i] else joined$value_integer[i]
    other <- if(sc$type=="free_text") joined$value_integer[i] else joined$value_text[i]
    ensure(is.na(other),"responses.wrong_value_type")
    validate_response(value,joined$answer_status[i],sc)
  }
  ensure(whole(round_number)&&length(round_number)==1&&round_number>0,"round_number")
  h <- content_hash(list(data=joined,items=items,protocol=protocol,round_number=round_number))
  structure(list(data=joined,items=items,protocol=protocol,round_number=round_number,
    snapshot_id=if(is.null(snapshot_id)) h else snapshot_id,content_hash=h,schema_version="1.0"),class="delphyr_snapshot")
}
#' Synthetic offline snapshot
#' @param values Integer ratings; NA creates an explicit not_answered response.
#' @param groups Optional group assignments.
#' @return Validated synthetic snapshot.
#' @export
#' @examples
#' analyse_round(demo_snapshot())$results
 demo_snapshot <- function(values=c(1,4,6,7,7,8,8,9,9,9),groups=rep("professionals",length(values))) {
  p <- demo_protocol(); p$analysis$consensus$group_policy <- "pooled"
  a <- data.frame(panelist_id=sprintf("P%03d",seq_along(values)),group_code=groups,submitted=TRUE)
  i <- data.frame(item_code="I001",item_version=1L,dimension_code="relevance",scale_code="relevance_9")
  r <- data.frame(panelist_id=a$panelist_id,item_code="I001",item_version=1L,dimension_code="relevance",
    answer_status=ifelse(is.na(values),"not_answered","answered"),value_integer=values,value_text=NA_character_)
  new_snapshot(r,a,i,p)
}
#' Analyse a frozen round independently of the application
#' @param snapshot Validated delphyr_snapshot.
#' @param rules Consensus rule; defaults to the frozen protocol.
#' @return delphyr_analysis containing results, denominators, missingness,
#'   distributions, settings, warnings and scientific provenance.
#' @export
#' @examples
#' summary(analyse_round(demo_snapshot()))
analyse_round <- function(snapshot,rules=snapshot$protocol$analysis$consensus) {
  ensure(inherits(snapshot,"delphyr_snapshot"),"snapshot")
  # Verify content, so modifying a serialized snapshot cannot silently change provenance.
  ensure(identical(snapshot$content_hash,content_hash(list(data=snapshot$data,items=snapshot$items,
    protocol=snapshot$protocol,round_number=snapshot$round_number))),"snapshot.hash")
  validate_rule(rules)
  groups <- unlist(snapshot$protocol$panel$groups)
  strata <- c("overall",groups)
  result <- distribution <- list()
  scales <- config_scales(snapshot$protocol)
  for(j in seq_len(nrow(snapshot$items))) {
    it <- snapshot$items[j,,drop=FALSE]; sc <- scales[[it$scale_code]]
    if(sc$type != "free_text") validate_rule(rules,sc)
    for(g in strata) {
      z <- snapshot$data
      z <- z[z$item_code==it$item_code & z$item_version==it$item_version & z$dimension_code==it$dimension_code & (g=="overall"|z$group_code==g),,drop=FALSE]
      valid <- z$submitted & z$answer_status=="answered"
      x <- z$value_integer[valid]
      if(sc$type=="free_text") x <- numeric()
      counts <- list(n_valid=length(x),n_agree=sum(x %in% unlist(rules$agree_values)),n_disagree=sum(x %in% unlist(rules$disagree_values)))
      cl <- classify_consensus(counts,rules)
      q <- if(length(x)) stats::quantile(x,c(.25,.5,.75),type=7,names=FALSE) else rep(NA_real_,3)
      result[[length(result)+1L]] <- data.frame(round_number=snapshot$round_number,it,stratum=g,
        n_assigned=nrow(z),n_submitted=sum(z$submitted),n_answered=sum(valid),
        n_not_answered=sum(z$answer_status=="not_answered"),n_unable=sum(z$answer_status=="unable_to_judge"),
        n_abstained=sum(z$answer_status=="abstained"),n_not_applicable=sum(z$answer_status=="not_applicable"),
        as.data.frame(cl),median=q[2],q1=q[1],q3=q[3],iqr=q[3]-q[1],stringsAsFactors=FALSE)
      if(length(sc$levels)) distribution[[length(distribution)+1L]] <- data.frame(it,stratum=g,
        value=sc$levels,n=vapply(sc$levels,function(v)sum(x==v),integer(1)))
    }
  }
  res <- do.call(rbind,result); rownames(res) <- NULL
  decisions <- res[res$stratum=="overall",c("item_code","item_version","dimension_code","classification"),drop=FALSE]
  if(rules$group_policy=="all_required_groups") for(i in seq_len(nrow(decisions))) {
    k <- decisions[i,]; st <- res$classification[res$item_code==k$item_code & res$item_version==k$item_version & res$dimension_code==k$dimension_code & res$stratum %in% groups]
    decisions$classification[i] <- if(any(st=="insufficient_data")) "insufficient_data" else if(all(st=="consensus_in")) "consensus_in" else if(all(st=="consensus_out")) "consensus_out" else "no_consensus"
  }
  dist <- if(length(distribution)) do.call(rbind,distribution) else data.frame()
  structure(list(results=res,decisions=decisions,distributions=dist,
    denominators=res[,c("item_code","item_version","dimension_code","stratum","n_assigned","n_submitted","n_valid","n_agree","n_disagree")],
    missingness=res[,c("item_code","item_version","dimension_code","stratum","n_not_answered","n_unable","n_abstained","n_not_applicable")],
    settings=rules,provenance=list(snapshot_id=snapshot$snapshot_id,snapshot_hash=snapshot$content_hash,
      rules_hash=content_hash(rules),software_version="0.0.1",quantile_type=7,
      result_hash=content_hash(list(results=res,decisions=decisions,distributions=dist))),
    warnings=character(),schema_version="1.0"),class="delphyr_analysis")
}
#' Compare paired responses across compatible rounds
#' @param previous,current Validated snapshots.
#' @param mapping Optional table item_code, dimension_code, previous_version,
#'   current_version, comparable, reason. Explicit approval required for new versions.
#' @return delphyr_comparison table, reporting attrition and unpaired means separately.
#' @export
#' @examples
#' compare_rounds(demo_snapshot(c(5,7,8,9)), demo_snapshot(c(6,7,7,9)))
compare_rounds <- function(previous,current,mapping=NULL) {
  analyse_round(previous); analyse_round(current)
  out <- list()
  for(i in seq_len(nrow(current$items))) {
    it <- current$items[i,]; old <- previous$items[previous$items$item_code==it$item_code & previous$items$dimension_code==it$dimension_code,,drop=FALSE]
    comparable <- nrow(old)==1 && old$item_version==it$item_version && old$scale_code==it$scale_code
    reason <- if(comparable) "unchanged" else "changed_or_new_item"
    if(!is.null(mapping)) {
      ensure(is.data.frame(mapping)&&all(c("item_code","dimension_code","previous_version","current_version","comparable","reason")%in%names(mapping)),"mapping")
      m <- mapping[mapping$item_code==it$item_code & mapping$dimension_code==it$dimension_code,,drop=FALSE]
      ensure(nrow(m)<=1,"mapping.duplicate")
      if(nrow(m)) {
        comparable <- isTRUE(m$comparable) && nrow(old)==1 && m$previous_version==old$item_version && m$current_version==it$item_version
        reason <- m$reason
      }
    }
    if(nrow(old)==1) comparable <- comparable && identical(config_scales(previous$protocol)[[old$scale_code]],config_scales(current$protocol)[[it$scale_code]])
    subset_valid <- function(s) { z<-s$data; z[z$item_code==it$item_code & z$dimension_code==it$dimension_code & z$submitted & z$answer_status=="answered" & !is.na(z$value_integer),c("panelist_id","value_integer"),drop=FALSE] }
    a<-subset_valid(previous); b<-subset_valid(current); pairs<-merge(a,b,by="panelist_id")
    d<-pairs$value_integer.y-pairs$value_integer.x
    n<-if(comparable)length(d) else 0L
    out[[i]]<-data.frame(item_code=it$item_code,dimension_code=it$dimension_code,
      status=if(!comparable)"not_comparable" else if(!n)"insufficient_data" else "descriptive",
      reason=reason,n_paired=n,n_previous=nrow(a),n_current=nrow(b),
      n_lost=length(setdiff(a$panelist_id,b$panelist_id)),n_new=length(setdiff(b$panelist_id,a$panelist_id)),
      previous_mean=if(nrow(a))mean(a$value_integer) else NA_real_,current_mean=if(nrow(b))mean(b$value_integer) else NA_real_,
      mean_absolute_change=if(n)mean(abs(d)) else NA_real_,median_absolute_change=if(n)stats::median(abs(d)) else NA_real_,
      proportion_unchanged=if(n)mean(d==0) else NA_real_,proportion_within_one=if(n)mean(abs(d)<=1) else NA_real_)
  }
  structure(do.call(rbind,out),class=c("delphyr_comparison","data.frame"))
}
#' @export
print.delphyr_analysis <- function(x,...) { print(x$decisions,row.names=FALSE); invisible(x) }
#' @export
summary.delphyr_analysis <- function(object,...) object$results
#' @export
as.data.frame.delphyr_analysis <- function(x,...) x$results
