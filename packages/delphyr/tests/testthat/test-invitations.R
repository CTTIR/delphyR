invitation_fixture <- function(env=parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB")!="true","PostgreSQL opt-in")
  r<-connect_repository(host="127.0.0.1",port=55439,dbname="delphyr",user="postgres",environment="test")
  withr::defer(DBI::dbDisconnect(r$con),envir=env)
  f<-demo_study(r,n=2L,item_count=1L)
  csv<-paste("external_ref,email,display_name,locale,stakeholder_group","a,a@example.invalid,Synthetic,de,professionals",sep="\n")
  preview<-preview_panel_import(r,f$manager,f$study_id,csv)
  imported<-import_panel(r,f$manager,f$study_id,preview,preview$hash,"Synthetic review","import")
  id<-uid();issuer<-"https://synthetic.example.invalid";subject<-uid()
  execute(r,"INSERT INTO identity.principals(id,issuer,subject) VALUES($1,$2,$3)",id,issuer,subject)
  config<-new_authentication_config(issuer,paste(rep("a",64),collapse=""),"127.0.0.1")
  actor<-authenticated_actor(r,list(REMOTE_ADDR="127.0.0.1",HTTP_X_DELPHYR_GATEWAY=config$gateway_secret,HTTP_X_FORWARDED_USER=subject),config)
  list(repo=r,fixture=f,draft=imported$invitation_ids[[1]],actor=actor)
}
invitation_issue_test <- function(f,token=new_invitation_token(),ttl=900L,key="issue") {
  x<-issue_panel_invitation(f$repo,f$fixture$manager,f$fixture$study_id,f$draft,f$actor$principal_id,token,ttl,"Approved exact synthetic account",key)
  list(id=x$id,token=token)
}
test_that("private random tokens have 256 bits and redacted printing",{
  x<-new_invitation_token();y<-new_invitation_token()
  expect_match(as.character(x),"^[0-9a-f]{64}$")
  expect_false(identical(x,y))
  expect_false(grepl(as.character(x),paste(capture.output(print(x)),collapse=""),fixed=TRUE))
})
test_that("confirmed exact-account acceptance is atomic, single use and retry safe",{
  f<-invitation_fixture();r<-f$repo;s<-f$fixture$study_id;i<-invitation_issue_test(f)
  expect_identical(invitation_issue_test(f,i$token)$id,i$id)
  expect_error(accept_panel_invitation(r,f$actor,s,i$id,i$token,FALSE,"accept"),class="DEL_VALIDATION")
  expect_error(accept_panel_invitation(r,f$fixture$panel[[1]],s,i$id,i$token,TRUE,"accept"),class="DEL_UNAUTHORIZED")
  expect_error(accept_panel_invitation(r,f$actor,s,i$id,new_invitation_token(),TRUE,"accept"),class="DEL_UNAUTHORIZED")
  a<-accept_panel_invitation(r,f$actor,s,i$id,i$token,TRUE,"accept")
  expect_identical(accept_panel_invitation(r,f$actor,s,i$id,i$token,TRUE,"accept"),a)
  expect_error(accept_panel_invitation(r,f$actor,s,i$id,i$token,TRUE,"another"),class="DEL_CONFLICT")
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_invitation_acceptances WHERE invitation_id=$1",i$id)$n,1)
  expect_equal(query(r,"SELECT count(*) AS n FROM research.enrollments WHERE study_id=$1 AND panelist_id=$2",s,a$panelist_id)$n,0)
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.consents WHERE study_id=$1 AND membership_id=$2",s,a$membership_id)$n,0)
  stored<-query(r,"SELECT token_hash FROM identity.panel_invitations WHERE id=$1",i$id)$token_hash
  expect_false(identical(stored,as.character(i$token)))
  all_commands<-query(r,"SELECT outcome::text FROM ops.commands WHERE study_id=$1",s)$outcome
  expect_false(any(grepl(as.character(i$token),all_commands,fixed=TRUE)))
  expect_error(transaction(r,function()execute(r,"UPDATE identity.panel_invitations SET reason='changed' WHERE id=$1",i$id)),class="DEL_STORAGE")
})
test_that("revocation, expiry and current identity changes deny acceptance",{
  f<-invitation_fixture();r<-f$repo;s<-f$fixture$study_id;i<-invitation_issue_test(f)
  revoke_panel_invitation(r,f$fixture$manager,s,i$id,"Synthetic revoked","revoke")
  expect_error(accept_panel_invitation(r,f$actor,s,i$id,i$token,TRUE,"accept"),class="DEL_UNAUTHORIZED")
  expired<-invitation_issue_test(f,ttl=1L,key="short")
  Sys.sleep(1.1)
  expect_error(accept_panel_invitation(r,f$actor,s,expired$id,expired$token,TRUE,"accept"),class="DEL_UNAUTHORIZED")
  active<-invitation_issue_test(f,key="new")
  execute(r,"UPDATE identity.principals SET active=false WHERE id=$1",f$actor$principal_id)
  expect_error(accept_panel_invitation(r,f$actor,s,active$id,active$token,TRUE,"accept"),class="DEL_UNAUTHORIZED")
  execute(r,"UPDATE identity.principals SET active=true WHERE id=$1",f$actor$principal_id)
  wrong<-f$actor;wrong$issuer<-"https://wrong.example.invalid"
  expect_error(accept_panel_invitation(r,wrong,s,active$id,active$token,TRUE,"accept"),class="DEL_UNAUTHORIZED")
})
test_that("scanner preview is read only and discloses no contacts",{
  f<-invitation_fixture();i<-invitation_issue_test(f);s<-f$fixture$study_id;r<-f$repo
  before<-query(r,"SELECT count(*) AS n FROM identity.memberships WHERE study_id=$1",s)$n
  preview<-preview_panel_invitation(r,f$actor,s,i$id,i$token)
  expect_named(preview,c("id","study_title","expires_at"))
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.memberships WHERE study_id=$1",s)$n,before)
  wrong<-f$actor;wrong$principal_id<-f$fixture$manager$principal_id
  expect_error(preview_panel_invitation(r,wrong,s,i$id,i$token),class="DEL_UNAUTHORIZED")
  expect_error(accept_panel_invitation(r,f$actor,uid(),i$id,i$token,TRUE,"wrong-study"),class="DEL_NOT_FOUND")
})
test_that("two blocked independent consumers create exactly one membership",{
  skip_if_not_installed("callr")
  f<-invitation_fixture();i<-invitation_issue_test(f);s<-f$fixture$study_id;r<-f$repo
  base<-normalizePath("../..",mustWork=TRUE)
  if(!file.exists(file.path(base,"DESCRIPTION"))) base<-normalizePath("packages/delphyr",mustWork=TRUE)
  names<-paste0("invitation-",uid(),c("-a","-b"))
  run<-function(path,lib,actor,study,id,token,key,name){
    .libPaths(lib);pkgload::load_all(path,quiet=TRUE)
    r<-delphyr::connect_repository(host="127.0.0.1",port=55439,dbname="delphyr",user="postgres",environment="test",options=paste0("-c application_name=",name))
    on.exit(DBI::dbDisconnect(r$con))
    tryCatch({delphyr::accept_panel_invitation(r,actor,study,id,token,TRUE,key);"success"},error=function(e)class(e)[1L])
  }
  DBI::dbBegin(r$con);query(r,"SELECT id FROM research.studies WHERE id=$1 FOR UPDATE",s)
  locked<-TRUE;withr::defer(if(locked)DBI::dbRollback(r$con))
  a<-callr::r_bg(run,list(base,.libPaths(),f$actor,s,i$id,as.character(i$token),"a",names[1]))
  b<-callr::r_bg(run,list(base,.libPaths(),f$actor,s,i$id,as.character(i$token),"b",names[2]))
  withr::defer({if(a$is_alive())a$kill();if(b$is_alive())b$kill()})
  ready<-FALSE
  for(k in seq_len(100L)) {
    query(r,"SELECT pg_stat_clear_snapshot()")
    n<-query(r,"SELECT count(*) AS n FROM pg_stat_activity WHERE application_name IN ($1,$2) AND wait_event_type='Lock'",names[1],names[2])$n
    if(n==2L){ready<-TRUE;break};Sys.sleep(0.1)
  }
  expect_true(ready)
  DBI::dbCommit(r$con);locked<-FALSE
  a$wait(10000);b$wait(10000)
  expect_setequal(c(a$get_result(),b$get_result()),c("success","DEL_CONFLICT"))
  expect_equal(query(r,"SELECT count(*) AS n FROM identity.panel_invitation_acceptances WHERE invitation_id=$1",i$id)$n,1)
})
