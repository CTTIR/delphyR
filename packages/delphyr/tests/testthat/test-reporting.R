reporting_repo <- function(env=parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB")!="true","PostgreSQL opt-in required")
  r<-connect_repository(host="127.0.0.1",port=55439,dbname="delphyr",user="postgres",environment="test")
  withr::defer(DBI::dbDisconnect(r$con),envir=env)
  r
}
reporting_fixture <- function(r,submitted=FALSE) {
  f<-demo_study(r,n=2L,item_count=1L)
  for(state in c("review","approved","open","closed")) {
    transition_round(r,f$manager,f$round$id,state,f$round$hash,"Synthetic report",state)
    if(state=="open"&&submitted) for(actor in f$panel) {
      record_consent(r,actor,f$study_id,f$consent_id,TRUE,"consent")
      enrollment<-list_enrollments(r,actor,f$study_id)$id[1]
      item<-get_questionnaire(r,actor,enrollment)$items$id[1]
      save_response(r,actor,enrollment,item,list(value=7L,status="answered"),0L,"save")
      submit_round(r,actor,enrollment,setNames(1L,item),"submit")
    }
  }
  f$snapshot<-freeze_round(r,f$manager,f$round$id,"freeze")$id
  f$analysis<-run_analysis(r,f$manager,f$snapshot,"analysis")$id
  f
}
test_that("report supplement requires export rights and excludes qualitative source text",{
  r<-reporting_repo();f<-reporting_fixture(r);other<-reporting_fixture(r)
  record_item_decision(r,f$manager,f$analysis,"I001","rerate","PRIVATE-REASON-MUST-NOT-EXPORT","decision")
  set_capability(r,f$manager,f$study_id,f$manager$principal_id,"analyse",FALSE,"no-analysis")
  data<-prepare_report_data(r,f$manager,f$snapshot)
  expect_s3_class(data,"delphyr_report_data")
  expect_equal(nrow(data$instrument),2L)
  expect_identical(data$decisions$disposition,"rerate")
  expect_true(all(data$author_fields$status=="nicht dokumentiert"))
  expect_false(grepl("PRIVATE-REASON-MUST-NOT-EXPORT",json(unclass(data)),fixed=TRUE))
  expect_false(any(c("actor_id","principal_id","original_text","value_text") %in% unlist(lapply(data,names))))
  expect_error(prepare_report_data(r,other$manager,f$snapshot),class="DEL_NOT_FOUND")
  expect_error(prepare_report_data(r,f$panel[[1]],f$snapshot),class="DEL_FORBIDDEN")
  set_capability(r,f$manager,f$study_id,f$manager$principal_id,"export",FALSE,"no-export")
  expect_error(prepare_report_data(r,f$manager,f$snapshot),class="DEL_FORBIDDEN")
})
test_that("supplement exports are allowlisted and preserve integrity",{
  r<-reporting_repo();f<-reporting_fixture(r)
  data<-prepare_report_data(r,f$manager,f$snapshot)
  directory<-tempfile("report-data-");dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  files<-write_report_data(data,directory)
  expect_setequal(list.files(directory),files)
  expect_true(file.exists(file.path(directory,"round_items.csv")))
  expect_true(file.exists(file.path(directory,"data_dictionary.csv")))
  expect_error(write_report_data(data,directory),class="DEL_CONFLICT")
  altered<-data;altered$metadata$study_title<-"Altered without recomputing hash"
  expect_error(write_report_data(altered,directory),class="DEL_VALIDATION")
})
test_that("trusted Quarto rendering escapes input instead of executing study content",{
  skip_if(!nzchar(Sys.which("quarto")),"Quarto executable not installed")
  skip_if_not_installed("rmarkdown")
  r<-reporting_repo();f<-reporting_fixture(r)
  data<-prepare_report_data(r,f$manager,f$snapshot)
  # Deliberately hostile *data* with an updated integrity hash tests the renderer boundary.
  marker<-file.path(tempdir(),paste0("render-execution-",uuid::UUIDgenerate()))
  hostile<-paste0("<script id='study-injection'>alert(1)</script> `r file.create(\"",marker,"\")` {{< include /etc/passwd >}}")
  data$instrument$text[1]<-hostile
  data$metadata$study_title<-hostile
  data$content_hash<-NULL;data$content_hash<-content_hash(unclass(data))
  directory<-tempfile("report-render-");dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  before<-getwd()
  html<-render_study_report(data,directory,timeout=60L)
  expect_identical(getwd(),before)
  content<-paste(readLines(html,warn=FALSE),collapse="\n")
  expect_false(file.exists(marker))
  expect_false(grepl("<script id='study-injection'>",content,fixed=TRUE))
  expect_true(grepl("&lt;script",content,fixed=TRUE))
  expect_true(grepl("nicht dokumentiert",content,fixed=TRUE))
  expect_true(grepl(data$provenance$result_hash,content,fixed=TRUE))
  expect_error(render_study_report(data,directory),class="DEL_CONFLICT")
})

test_that("worker export manifests include supplements and inert hostile instrument text",{
  skip_if(!nzchar(Sys.which("quarto")),"Quarto executable not installed")
  skip_if_not_installed("rmarkdown")
  r<-reporting_repo();f<-reporting_fixture(r,submitted=TRUE)
  r$artifact_root<-tempfile("worker-report-")
  withr::defer(unlink(r$artifact_root,recursive=TRUE))
  transition_round(r,f$manager,f$round$id,"finalized",f$round$hash,"Synthetic next round","finalize")
  marker<-file.path(tempdir(),paste0("export-execution-",uuid::UUIDgenerate()))
  hostile<-paste0("<script id='export-injection'>alert(1)</script> `r file.create(\"",marker,"\")`")
  f$items$text<-hostile
  f$items$item_version<-2L
  second<-prepare_round(r,f$manager,f$study_id,f$items,f$consent_id,
    format(Sys.time()+3600,"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),"second")
  for(state in c("review","approved","open","closed"))transition_round(r,f$manager,second$id,state,second$hash,"Synthetic report",paste0("second-",state))
  snapshot<-freeze_round(r,f$manager,second$id,"second-freeze")$id
  job<-request_export(r,f$manager,snapshot,"export")
  outcome<-worker_step(r,f$study_id)
  expect_identical(outcome$id,job$id)
  expect_identical(outcome$state,"succeeded")
  path<-download_artifact(r,f$manager,outcome$result_ref)
  manifest<-from_json(paste(readLines(file.path(path,"manifest.json")),collapse="\n"))
  names<-vapply(manifest$files,`[[`,character(1),"name")
  expect_true(all(c("report.html","report-data.json","round_items.csv","data_dictionary.csv",
    "item_decisions.csv","item_lineage.csv","missingness.csv","author_fields.csv") %in% names))
  expect_identical(manifest$report$renderer,"quarto_html")
  expect_setequal(c(names,"manifest.json"),list.files(path))
  expect_identical(reproduce_export(path)$provenance$result_hash,manifest$result_hash)
  html<-paste(readLines(file.path(path,"report.html"),warn=FALSE),collapse="\n")
  expect_false(file.exists(marker))
  expect_false(grepl("<script id='export-injection'>",html,fixed=TRUE))
  expect_true(grepl("&lt;script",html,fixed=TRUE))
  write("tampered",file.path(path,"data_dictionary.csv"))
  expect_error(download_artifact(r,f$manager,outcome$result_ref),class="DEL_VALIDATION")
})

test_that("only absent optional runtime selects the labeled basic fallback",{
  r<-reporting_repo();f<-reporting_fixture(r)
  r$artifact_root<-tempfile("fallback-report-")
  withr::defer(unlink(r$artifact_root,recursive=TRUE))
  local_mocked_bindings(render_study_report=function(...)del_abort("DEL_DEPENDENCY","report.quarto_runtime"),.package="delphyr")
  job<-request_export(r,f$manager,f$snapshot,"export")
  outcome<-worker_step(r,f$study_id)
  expect_identical(outcome$id,job$id)
  expect_identical(outcome$state,"succeeded")
  path<-download_artifact(r,f$manager,outcome$result_ref)
  manifest<-from_json(paste(readLines(file.path(path,"manifest.json")),collapse="\n"))
  expect_identical(manifest$report$renderer,"basic_html_missing_quarto_runtime")
  expect_true(grepl("HTML-Fallback",paste(readLines(file.path(path,"report.html")),collapse="\n"),fixed=TRUE))
  expect_true(file.exists(file.path(path,"report-data.json")))
})

test_that("render failure fails the export operation and leaves no artifact",{
  r<-reporting_repo();f<-reporting_fixture(r)
  r$artifact_root<-tempfile("failed-report-")
  withr::defer(unlink(r$artifact_root,recursive=TRUE))
  local_mocked_bindings(render_study_report=function(...)del_abort("DEL_RENDER","report.render_failed"),.package="delphyr")
  job<-request_export(r,f$manager,f$snapshot,"export")
  outcome<-worker_step(r,f$study_id)
  expect_identical(outcome$id,job$id)
  expect_identical(outcome$state,"failed")
  expect_identical(outcome$error_code,"DEL_RENDER")
  expect_length(list.files(r$artifact_root,all.files=TRUE,no..=TRUE),0L)
  expect_equal(query(r,"SELECT count(*) AS n FROM ops.artifacts WHERE study_id=$1",f$study_id)$n,0)
  expect_identical(get_operation(r,f$manager,job$id)$state,"retry_wait")
})


test_that("report lineage is scoped to exact frozen item versions",{
  r<-reporting_repo();f<-reporting_fixture(r,submitted=TRUE)
  transition_round(r,f$manager,f$round$id,"finalized",f$round$hash,"Synthetic next round","finalize")
  revised<-f$items;revised$item_version<-2L;revised$text<-paste(revised$text,"revised")
  prepare_round(r,f$manager,f$study_id,revised,f$consent_id,
    format(Sys.time()+3600,"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),"next-round")
  record_item_lineage(r,f$manager,f$study_id,
    data.frame(item_code="I001",item_version=2L),
    data.frame(item_code=c("NEW_A","NEW_B"),item_version=1L),
    "split","Later version only","later-split")
  expect_equal(nrow(prepare_report_data(r,f$manager,f$snapshot)$lineage),0L)
  record_item_lineage(r,f$manager,f$study_id,
    data.frame(item_code="I001",item_version=1L),
    data.frame(item_code=c("OLD_A","OLD_B"),item_version=1L),
    "split","Frozen version lineage","frozen-split")
  lineage<-prepare_report_data(r,f$manager,f$snapshot)$lineage
  expect_setequal(lineage$child_item,c("OLD_A","OLD_B"))
  expect_true(all(lineage$parent_version==1L))
})
