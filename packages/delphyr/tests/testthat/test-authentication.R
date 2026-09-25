auth_test_config <- function() new_authentication_config("http://127.0.0.1:4190/realms/test",
  paste(rep("a",64),collapse=""),"127.0.0.1",60L)
auth_test_request <- function() list(REMOTE_ADDR="127.0.0.1",
  HTTP_X_DELPHYR_GATEWAY=paste(rep("a",64),collapse=""),HTTP_X_FORWARDED_USER="stable-subject")

test_that("gateway configuration and unauthenticated transport fail closed", {
  expect_error(new_authentication_config("not-an-issuer","short","127.0.0.1"),class="DEL_VALIDATION")
  expect_error(new_authentication_config("https://issuer.example","short","127.0.0.1"),class="DEL_VALIDATION")
  expect_error(new_authentication_config("https://issuer.example",paste(rep("a",64),collapse=""),"127.0.0.1",3601),class="DEL_VALIDATION")
  config<-auth_test_config()
  expect_error(authenticated_actor(NULL,list(),config),class="DEL_UNAUTHORIZED")
  req<-auth_test_request();req$REMOTE_ADDR<-"203.0.113.4"
  expect_error(authenticated_actor(NULL,req,config),class="DEL_UNAUTHORIZED")
  req<-auth_test_request();req$HTTP_X_DELPHYR_GATEWAY<-NULL
  expect_error(authenticated_actor(NULL,req,config),class="DEL_UNAUTHORIZED")
  req<-auth_test_request();req$HTTP_X_DELPHYR_GATEWAY<-"browser-forgery"
  expect_error(authenticated_actor(NULL,req,config),class="DEL_UNAUTHORIZED")
  req<-auth_test_request();req$HTTP_X_FORWARDED_USER<-c("one","two")
  expect_error(authenticated_actor(NULL,req,config),class="DEL_UNAUTHORIZED")
  req<-auth_test_request();req$HTTP_X_FORWARDED_USER<-"one,two"
  expect_error(authenticated_actor(NULL,req,config),class="DEL_UNAUTHORIZED")
})

test_that("only the configured issuer and stable subject map to a current principal", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB")!="true","Opt-in PostgreSQL tests")
  skip_if_not_installed("RPostgres")
  r<-connect_repository(host="127.0.0.1",port=55439,dbname="delphyr",user="postgres",environment="test")
  withr::defer(DBI::dbDisconnect(r$con))
  config<-auth_test_config();request<-auth_test_request()
  request$HTTP_X_FORWARDED_USER<-paste0("synthetic-",uuid::UUIDgenerate())
  id<-uuid::UUIDgenerate()
  delphyr:::execute(r,"INSERT INTO identity.principals(id,issuer,subject) VALUES($1,$2,$3)",id,config$issuer,request$HTTP_X_FORWARDED_USER)
  before<-Sys.time();actor<-authenticated_actor(r,list2env(request),config)
  expect_identical(actor$principal_id,id)
  expect_true(as.numeric(difftime(actor$expires_at,before,units="secs"))>=60)
  expect_true(as.numeric(difftime(actor$expires_at,before,units="secs"))<62)
  # Browser role/principal/email headers cannot select a different identity.
  request$HTTP_X_FORWARDED_EMAIL<-"admin@example.invalid";request$principal_id<-uuid::UUIDgenerate();request$role<-"manage"
  expect_identical(authenticated_actor(r,request,config)$principal_id,id)
  expect_equal(nrow(list_studies(r,actor)),0L)
  wrong<-config;wrong$issuer<-"https://different.example/realm"
  expect_error(authenticated_actor(r,request,wrong),class="DEL_UNAUTHORIZED")
  unknown<-request;unknown$HTTP_X_FORWARDED_USER<-"unknown"
  expect_error(authenticated_actor(r,unknown,config),class="DEL_UNAUTHORIZED")
  delphyr:::execute(r,"UPDATE identity.principals SET active=false WHERE id=$1",id)
  expect_error(authenticated_actor(r,request,config),class="DEL_UNAUTHORIZED")
  expect_error(list_studies(r,actor),class="DEL_UNAUTHORIZED")
  delphyr:::execute(r,"UPDATE identity.principals SET active=true WHERE id=$1",id)
  actor$expires_at<-Sys.time()-1
  expect_error(list_studies(r,actor),class="DEL_UNAUTHORIZED")
})

test_that("printing gateway configuration does not reveal the private secret", {
  config<-auth_test_config()
  output<-paste(capture.output(print(config)),collapse="\n")
  expect_false(grepl(config$gateway_secret,output,fixed=TRUE))
  expect_match(output,"<redacted>",fixed=TRUE)
})
