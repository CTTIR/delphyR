#' Structured delphyr error
#' @param code Stable condition code.
#' @param path Field path, without sensitive values.
#' @return Does not return; signals a structured error.
#' @export
#' @examples
#' tryCatch(del_abort("DEL_VALIDATION", "scale"), error = function(e) e$code)
del_abort <- function(code, path = "") {
  stop(structure(list(message = paste(code, path), call = NULL,
    code = code, path = path), class = c(code, "delphyr_error", "error", "condition")))
}
ensure <- function(ok, path, code = "DEL_VALIDATION") {
  if (!isTRUE(ok)) del_abort(code, path)
}
scalar_text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
whole <- function(x) is.numeric(x) && length(x) > 0L && all(is.finite(x) & x == floor(x))
known_keys <- function(x, keys, path, required = keys) {
  ensure(is.list(x) && !is.null(names(x)) && !anyDuplicated(names(x)), path)
  ensure(all(names(x) %in% keys) && all(required %in% names(x)), path)
}
canonical <- function(x) {
  if (is.data.frame(x)) {
    x <- x[, sort(names(x)), drop = FALSE]
    if (nrow(x)) x <- x[do.call(order, c(unname(x), list(na.last = TRUE))), , drop = FALSE]
    rownames(x) <- NULL
    return(lapply(seq_len(nrow(x)), function(i) canonical(as.list(x[i, , drop = FALSE]))))
  }
  if (is.list(x)) {
    if (!is.null(names(x))) x <- x[sort(names(x))]
    return(lapply(x, canonical))
  }
  unname(x)
}
#' Canonical scientific content hash
#' @param x Declarative data; data frame row order is ignored.
#' @return SHA-256 string of sorted UTF-8 JSON, excluding no fields implicitly.
#' @export
#' @examples
#' content_hash(list(b = 2, a = 1))
content_hash <- function(x) digest::digest(jsonlite::toJSON(canonical(x),
  auto_unbox = TRUE, null = "null", na = "null", digits = NA), algo = "sha256", serialize = FALSE)
json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
from_json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)
