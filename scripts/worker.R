.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
r <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "development", artifact_root = file.path(getwd(), ".artifacts"))
repeat {
  result <- delphyr::worker_step(r)
  message_result <- delphyr::process_campaign_sink(r)
  if (identical(result, FALSE) && identical(message_result, FALSE)) Sys.sleep(1)
}
