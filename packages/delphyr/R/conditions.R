#' Structured delphyr error
#' @param code Stable condition code.
#' @param path Field path, without sensitive values.
#' @return Does not return; signals a structured error.
#' @export
#' @examples
#' tryCatch(del_abort("DEL_VALIDATION", "scale"), error = function(e) e$code)
del_abort <- function(code, path = "") {
  stop(structure(list(
    message = paste(code, path), call = NULL,
    code = code, path = path
  ), class = c(code, "delphyr_error", "error", "condition")))
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
  # Tagged JSON preserves structural identities. Integers and doubles share
  # numeric semantics, as required by JSON database round trips.
  if (is.data.frame(x)) {
    ensure(!anyDuplicated(names(x)), "hash.columns")
    x <- x[, sort(names(x), method = "radix"), drop = FALSE]
    if (nrow(x)) x <- x[do.call(order, c(unname(x), list(na.last = TRUE, method = "radix"))), , drop = FALSE]
    rownames(x) <- NULL
    return(list(
      kind = "table", columns = as.list(names(x)),
      rows = lapply(seq_len(nrow(x)), function(i) canonical(as.list(x[i, , drop = FALSE])))
    ))
  }
  if (is.null(x)) {
    return(list(kind = "null"))
  }
  if (!is.null(names(x))) {
    ensure(!anyNA(names(x)) && !anyDuplicated(names(x)) && all(nzchar(names(x))), "hash.names")
    x <- x[order(names(x), method = "radix")]
    return(list(kind = "object", entries = lapply(seq_along(x), function(i) {
      list(key = enc2utf8(names(x)[i]), value = canonical(x[[i]]))
    })))
  }
  if (is.list(x) || length(x) != 1L) {
    ensure(is.list(x) || is.atomic(x), "hash.type")
    return(list(kind = "array", values = lapply(as.list(x), canonical)))
  }
  ensure(is.character(x) || is.numeric(x) || is.logical(x), "hash.type")
  # Missing scalar values are type-independent: an all-null JSON column has
  # no recoverable R storage type. A missing value is distinct from NULL.
  if (is.na(x)) {
    return(list(kind = "missing"))
  }
  if (is.numeric(x)) {
    ensure(is.finite(x), "hash.finite")
    return(list(kind = "number", value = as.numeric(x)))
  }
  if (is.character(x)) {
    return(list(kind = "string", value = enc2utf8(x)))
  }
  list(kind = "boolean", value = x)
}
#' Canonical scientific content hash
#' @param x Declarative data; data frame row order is ignored.
#' @return SHA-256 string of sorted UTF-8 JSON, excluding no fields implicitly.
#' @export
#' @examples
#' content_hash(list(b = 2, a = 1))
content_hash <- function(x) {
  digest::digest(jsonlite::toJSON(canonical(x),
    auto_unbox = TRUE, null = "null", na = "null", digits = NA
  ), algo = "sha256", serialize = FALSE)
}
json <- function(x) {
  if (is.object(x) && is.list(x) && !is.data.frame(x)) x <- unclass(x)
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
}
from_json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)

#' @importFrom stats setNames
NULL
