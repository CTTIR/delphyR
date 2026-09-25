# UI translations are exact keys; study content remains protocol-controlled.
translation_catalog <- local({
  catalog <- NULL
  function() {
    if (is.null(catalog)) {
      path <- system.file("i18n", "fr.tsv", package = "delphyrApp")
      data <- utils::read.delim(path, header = FALSE, quote = "", comment.char = "", fileEncoding = "UTF-8", stringsAsFactors = FALSE)
      if (anyDuplicated(data[[1]]) || any(!nzchar(data[[2]]))) stop("Invalid French translation catalog.", call. = FALSE)
      catalog <<- stats::setNames(data[[2]], data[[1]])
    }
    catalog
  }
})
translation_sources <- new.env(parent = emptyenv())

tr <- function(lang, de, en) {
  if (is.null(lang) || !length(lang)) lang <- "en"
  if (length(lang) != 1L || is.na(lang) || !lang %in% c("en", "fr", "de")) stop("Unsupported interface language.", call. = FALSE)
  if (length(de) != length(en)) stop("Translation vectors must have equal lengths.", call. = FALSE)
  for (i in seq_along(en)) translation_sources[[en[[i]]]] <- de[[i]]
  if (identical(lang, "de")) return(de)
  if (identical(lang, "en")) return(en)
  catalog <- translation_catalog()
  missing <- setdiff(unname(en), names(catalog))
  if (length(missing)) stop(paste("Missing French UI translation:", paste(missing, collapse = "; ")), call. = FALSE)
  out <- unname(catalog[en])
  names(out) <- names(en)
  out
}

# Status prefixes are registered interface text, never participant content.
# Preserve opaque receipt identifiers and timestamps after the translated prefix.
localize_status <- function(value, lang) {
  if (!length(value) || !nzchar(value)) return(value)
  english <- ls(translation_sources, all.names = TRUE)
  german <- vapply(english, function(key) translation_sources[[key]], character(1))
  french <- unname(translation_catalog()[english])
  sources <- c(english, german, french)
  keys <- rep(english, 3L)
  good <- !is.na(sources) & nzchar(sources)
  sources <- sources[good]
  keys <- keys[good]
  order <- order(nchar(sources), decreasing = TRUE)
  for (i in order) {
    prefix <- sources[[i]]
    # Appended metadata is separated by whitespace; partial words never match.
    suffix <- substring(value, nchar(prefix) + 1L)
    if (startsWith(value, prefix) && (!nzchar(suffix) || grepl("^[[:space:]]", suffix))) {
      key <- keys[[i]]
      return(paste0(tr(lang, translation_sources[[key]], key), suffix))
    }
  }
  value
}
