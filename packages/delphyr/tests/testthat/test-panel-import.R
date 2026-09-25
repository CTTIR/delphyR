panel_import_repo <- function(env=parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB")!="true","PostgreSQL opt-in required")
  r<-connect_repository(host="127.0.0.1",port=55439,dbname="delphyr",user="postgres",environment="test")
  withr::defer(DBI::dbDisconnect(r$con),envir=env)
  r
}
panel_import_csv <- function() paste(
  "external_ref,email,display_name,locale,stakeholder_group",
  "001,A.User+Tag@EXAMPLE.INVALID,Synthetic A,de,professionals",
  "NA,auser@example.invalid,Synthetic B,en,public_contributors",sep="\n")
panel_import_fixture <- function(r) demo_study(r,n=2L,item_count=1L)

test_that("panel preview preserves reference strings and conservatively normalizes domains",{
  r<-panel_import_repo();f<-panel_import_fixture(r)
  p<-preview_panel_import(r,f$manager,f$study_id,panel_import_csv())
  expect_true(p$valid)
  expect_identical(p$rows$external_ref,c("001","NA"))
  expect_identical(p$rows$normalized_email,c("A.User+Tag@example.invalid","auser@example.invalid"))
  expect_identical(p$file_hash,digest::digest(charToRaw(panel_import_csv()),algo="sha256",serialize=FALSE))
  expect_equal(p$accepted_rows,2L)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_contacts WHERE study_id=$1",f$study_id)$n,0)
  semi<-gsub(",",";",panel_import_csv(),fixed=TRUE)
  expect_true(preview_panel_import(r,f$manager,f$study_id,semi,delimiter=";")$valid)
  expect_error(preview_panel_import(r,f$manager,f$study_id,semi,schema_version="2.0"),class="DEL_VALIDATION")
})

test_that("row errors and duplicate review block the entire import without exposing values",{
  r<-panel_import_repo();f<-panel_import_fixture(r)
  duplicate<-paste(panel_import_csv(),"001,A.User+Tag@example.invalid,Synthetic C,de,unknown",sep="\n")
  p<-preview_panel_import(r,f$manager,f$study_id,duplicate)
  expect_false(p$valid)
  expect_true(all(c("duplicate_in_file","unknown_group") %in% p$issues$code))
  expect_true(all(p$issues$row %in% 1:3))
  expect_false(grepl("@",paste(unlist(p$issues),collapse=""),fixed=TRUE))
  expect_error(import_panel(r,f$manager,f$study_id,p,p$hash,"Reviewed test","bad"),class="DEL_VALIDATION")
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_import_receipts WHERE study_id=$1",f$study_id)$n,0)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_contacts WHERE study_id=$1",f$study_id)$n,0)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_invitation_drafts WHERE study_id=$1",f$study_id)$n,0)
  real<-preview_panel_import(r,f$manager,f$study_id,gsub("example.invalid","example.com",panel_import_csv(),fixed=TRUE))
  expect_true("synthetic_email_required" %in% real$issues$code)
  malformed<-preview_panel_import(r,f$manager,f$study_id,"email,email\na@example.invalid,b@example.invalid")
  expect_true("csv_schema_columns" %in% malformed$issues$code)
  case<-preview_panel_import(r,f$manager,f$study_id,sub("auser@example.invalid","a.user+tag@example.invalid",panel_import_csv(),fixed=TRUE))
  expect_true("email_case_review" %in% case$issues$code)
})

test_that("approved import creates only unbound drafts and has a durable idempotent receipt",{
  r<-panel_import_repo();f<-panel_import_fixture(r)
  counts<-query(r,"SELECT (SELECT count(*) FROM identity.principals p JOIN identity.memberships m ON m.principal_id=p.id WHERE m.study_id=$1) AS principals,(SELECT count(*) FROM identity.memberships WHERE study_id=$1) AS memberships,(SELECT count(*) FROM research.panelists WHERE study_id=$1) AS panelists",f$study_id)
  p<-preview_panel_import(r,f$manager,f$study_id,panel_import_csv())
  receipt<-import_panel(r,f$manager,f$study_id,p,p$hash,"Synthetic contacts reviewed","approved")
  expect_identical(import_panel(r,f$manager,f$study_id,p,p$hash,"Synthetic contacts reviewed","approved"),receipt)
  expect_equal(receipt$accepted_rows,2L)
  expect_length(receipt$invitation_ids,2L)
  expect_true(all(query(r,"SELECT state FROM identity.panel_invitation_drafts WHERE study_id=$1",f$study_id)$state=="unbound"))
  expect_identical(query(r,"SELECT (SELECT count(*) FROM identity.principals p JOIN identity.memberships m ON m.principal_id=p.id WHERE m.study_id=$1) AS principals,(SELECT count(*) FROM identity.memberships WHERE study_id=$1) AS memberships,(SELECT count(*) FROM research.panelists WHERE study_id=$1) AS panelists",f$study_id),counts)
  read<-get_panel_import_receipt(r,f$manager,receipt$id)
  expect_identical(read$receipt$file_hash,p$file_hash)
  expect_setequal(read$invitation_ids,receipt$invitation_ids)
  expect_false(any(grepl("email|display_name",names(read$receipt))))
  expect_error(import_panel(r,f$manager,f$study_id,p,p$hash,"Different approval","approved"),class="DEL_CONFLICT")
  again<-preview_panel_import(r,f$manager,f$study_id,panel_import_csv())
  expect_false(again$valid)
  expect_true(all(c("existing_external_ref","existing_email") %in% again$issues$code))
})

test_that("current coordination rights and study scope protect contact previews and receipts",{
  r<-panel_import_repo();f<-panel_import_fixture(r);other<-panel_import_fixture(r)
  expect_error(preview_panel_import(r,f$panel[[1]],f$study_id,panel_import_csv()),class="DEL_FORBIDDEN")
  expect_error(preview_panel_import(r,other$manager,f$study_id,panel_import_csv()),class="DEL_NOT_FOUND")
  p<-preview_panel_import(r,f$manager,f$study_id,panel_import_csv())
  expect_error(import_panel(r,other$manager,other$study_id,p,p$hash,"Wrong study","wrong"),class="DEL_VALIDATION")
  receipt<-import_panel(r,f$manager,f$study_id,p,p$hash,"Synthetic approval","approved")
  expect_error(get_panel_import_receipt(r,other$manager,receipt$id),class="DEL_NOT_FOUND")
  set_capability(r,f$manager,f$study_id,f$manager$principal_id,"coordinate",FALSE,"revoke")
  expect_error(get_panel_import_receipt(r,f$manager,receipt$id),class="DEL_FORBIDDEN")
  expect_error(import_panel(r,f$manager,f$study_id,p,p$hash,"Synthetic approval","approved"),class="DEL_FORBIDDEN")
})

test_that("stale duplicate previews and tampered approval data cannot write partially",{
  r<-panel_import_repo();f<-panel_import_fixture(r)
  p<-preview_panel_import(r,f$manager,f$study_id,panel_import_csv())
  changed<-p;changed$rows$display_name[1]<-"Changed after preview"
  expect_error(import_panel(r,f$manager,f$study_id,changed,p$hash,"Reason","changed"),class="DEL_CONFLICT")
  changed<-p;changed$csv<-charToRaw(sub("Synthetic A","Changed A",panel_import_csv(),fixed=TRUE))
  expect_error(import_panel(r,f$manager,f$study_id,changed,p$hash,"Reason","changed-source"),class="DEL_CONFLICT")
  import_panel(r,f$manager,f$study_id,p,p$hash,"First approval","first")
  expect_error(import_panel(r,f$manager,f$study_id,p,p$hash,"Second approval","second"),class="DEL_VALIDATION")
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_contacts WHERE study_id=$1",f$study_id)$n,2)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_import_receipts WHERE study_id=$1",f$study_id)$n,1)
  expect_equal(query(r,"SELECT count(*) AS n FROM ops.commands WHERE study_id=$1 AND command_type='panel_import'",f$study_id)$n,1)
})

test_that("a failure after the first inserted draft rolls back the entire import",{
  r<-panel_import_repo();f<-panel_import_fixture(r)
  p<-preview_panel_import(r,f$manager,f$study_id,panel_import_csv())
  original_execute<-execute
  inserted<-0L
  local_mocked_bindings(execute=function(repo,sql,...) {
    if(startsWith(sql,"INSERT INTO identity.panel_invitation_drafts")) {
      inserted<<-inserted+1L
      if(inserted==2L)del_abort("DEL_STORAGE","synthetic_mid_import_failure")
    }
    original_execute(repo,sql,...)
  },.package="delphyr")
  expect_error(import_panel(r,f$manager,f$study_id,p,p$hash,"Synthetic approval","rollback"),class="DEL_STORAGE")
  expect_equal(inserted,2L)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_contacts WHERE study_id=$1",f$study_id)$n,0)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_invitation_drafts WHERE study_id=$1",f$study_id)$n,0)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_import_receipts WHERE study_id=$1",f$study_id)$n,0)
  expect_equal(query(r,"SELECT count(*) AS n FROM ops.commands WHERE study_id=$1 AND command_type='panel_import'",f$study_id)$n,0)
})


test_that("ordinary LF and CRLF file terminators preserve exact hashes and valid rows",{
  r<-panel_import_repo();f<-panel_import_fixture(r)
  lf<-paste0(panel_import_csv(),"\n")
  crlf<-gsub("\n","\r\n",lf,fixed=TRUE)
  for(text in list(lf,crlf)) {
    bytes<-charToRaw(text)
    p<-preview_panel_import(r,f$manager,f$study_id,bytes)
    expect_true(p$valid)
    expect_equal(nrow(p$rows),2L)
    expect_identical(p$file_hash,digest::digest(bytes,algo="sha256",serialize=FALSE))
    expect_identical(p$rows$external_ref,c("001","NA"))
  }
})
