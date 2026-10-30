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
canonical <- function(x, tables = NULL, legacy = FALSE) {
  # Tagged JSON preserves structural identities. Integers and doubles share
  # numeric semantics, as required by JSON database round trips.
  if (is.data.frame(x)) {
    ensure(!anyDuplicated(names(x)), "hash.columns")
    x <- x[, sort(names(x), method = "radix"), drop = FALSE]
    if (nrow(x)) x <- x[do.call(order, c(unname(x), list(na.last = TRUE, method = "radix"))), , drop = FALSE]
    rownames(x) <- NULL
    # A table is written directly; its place is held by a unique marker.
    if (!is.null(tables)) {
      text <- table_json(x, digits = tables$digits)
      if (!is.null(text)) {
        key <- paste0("delphyr-table-", tables$token, "-", length(tables$text) + 1L)
        tables$text[[key]] <- text
        return(key)
      }
    }
    return(list(
      kind = "table", columns = as.list(names(x)),
      rows = lapply(seq_len(nrow(x)), function(i) canonical(as.list(x[i, , drop = FALSE]), legacy = legacy))
    ))
  }
  if (is.null(x)) {
    return(list(kind = "null"))
  }
  if (!is.null(names(x))) {
    ensure(!anyNA(names(x)) && !anyDuplicated(names(x)) && all(nzchar(names(x))), "hash.names")
    x <- x[order(names(x), method = "radix")]
    return(list(kind = "object", entries = lapply(seq_along(x), function(i) {
      list(key = enc2utf8(names(x)[i]), value = canonical(x[[i]], tables, legacy = legacy))
    })))
  }
  if (is.list(x) || length(x) != 1L) {
    ensure(is.list(x) || is.atomic(x), "hash.type")
    return(list(kind = "array", values = lapply(as.list(x), canonical, tables = tables, legacy = legacy)))
  }
  ensure(is.character(x) || is.numeric(x) || is.logical(x), "hash.type")
  # Missing scalar values are type-independent: an all-null JSON column has
  # no recoverable R storage type. A missing value is distinct from NULL.
  if (is.na(x)) {
    return(list(kind = "missing"))
  }
  if (is.numeric(x)) {
    ensure(is.finite(x), "hash.finite")
    # JSON readers and integer ratings do not retain the sign of zero. Treat
    # both zeros alike in v2; old stored hashes retain their original bytes.
    if (!legacy && x == 0) x <- 0
    return(list(kind = "number", value = as.numeric(x)))
  }
  if (is.character(x)) {
    return(list(kind = "string", value = enc2utf8(x)))
  }
  list(kind = "boolean", value = x)
}
# JSON text of each distinct value, exactly as the JSON writer formats it.
# Quotes inside a string are always escaped, so the separator between two
# strings of an array never occurs within one.
json_values <- function(v, strings, digits = 17L) {
  out <- rep(NA_character_, length(v))
  ok <- !is.na(v)
  if (!any(ok)) {
    return(out)
  }
  if (strings) {
    known <- unique(enc2utf8(v[ok]))
    text <- as.character(jsonlite::toJSON(c(known, "")))
    parts <- strsplit(paste0(substring(text, 3L, nchar(text) - 2L), "."), "\",\"", fixed = TRUE)[[1]]
    if (length(parts) != length(known) + 1L || !identical(parts[length(parts)], ".")) {
      return(NULL)
    }
    out[ok] <- paste0("\"", parts[match(enc2utf8(v[ok]), known)], "\"")
  } else {
    known <- unique(v[ok])
    text <- as.character(jsonlite::toJSON(known, digits = digits))
    parts <- strsplit(substring(text, 2L, nchar(text) - 1L), ",", fixed = TRUE)[[1]]
    if (length(parts) != length(known)) {
      return(NULL)
    }
    out[ok] <- parts[match(v[ok], known)]
  }
  out
}
# Canonical JSON of a sorted table, written column by column. It is byte for
# byte the text of the generic form above; a round of specification size has
# 90 000 rows, which the generic form serializes in more than a minute. NULL
# for a table the generic form has to handle.
table_json <- function(x, digits = 17L) {
  if (!ncol(x)) {
    return(NULL)
  }
  keys <- json_values(names(x), TRUE)
  cells <- vector("list", ncol(x))
  for (j in seq_along(x)) {
    v <- x[[j]]
    if (is.object(v) || !(is.character(v) || is.numeric(v) || is.logical(v))) {
      return(NULL)
    }
    if (is.numeric(v)) {
      v <- as.numeric(v)
      # Not a number is missing; an infinite value is refused.
      ensure(all(is.finite(v) | is.na(v)), "hash.finite")
      if (!is.na(digits)) v[!is.na(v) & v == 0] <- 0
    }
    kind <- if (is.character(v)) "string" else if (is.numeric(v)) "number" else "boolean"
    values <- if (is.logical(v)) ifelse(v, "true", "false") else json_values(v, is.character(v), digits)
    if (is.null(values) || is.null(keys)) {
      return(NULL)
    }
    cells[[j]] <- paste0("{\"key\":", keys[j], ",\"value\":", ifelse(is.na(v), "{\"kind\":\"missing\"}", paste0("{\"kind\":\"", kind, "\",\"value\":", values, "}")), "}")
  }
  rows <- if (nrow(x)) paste0("{\"kind\":\"object\",\"entries\":[", do.call(paste, c(cells, sep = ",")), "]}") else character()
  paste0("{\"kind\":\"table\",\"columns\":[", paste(keys, collapse = ","), "],\"rows\":[", paste(rows, collapse = ","), "]}")
}
canonical_json <- function(x, digits = 17L) {
  tables <- new.env(parent = emptyenv())
  tables$token <- uuid::UUIDgenerate()
  tables$text <- list()
  tables$digits <- digits
  text <- as.character(jsonlite::toJSON(canonical(x, tables, legacy = is.na(digits)), auto_unbox = TRUE, null = "null", na = "null", digits = digits))
  for (key in names(tables$text)) {
    marker <- paste0("\"", key, "\"")
    at <- regexpr(marker, text, fixed = TRUE)
    ensure(at > 0L, "hash.table")
    text <- paste0(substring(text, 1L, at - 1L), tables$text[[key]], substring(text, at + nchar(marker)))
  }
  text
}
#' Canonical scientific content hash
#' @param x Declarative data; data frame row order is ignored.
#' @param version Hash contract: "2" (default) preserves double precision;
#'   "1" reproduces the legacy 15-digit JSON contract for existing records only.
#' @return SHA-256 string of sorted UTF-8 JSON, excluding no fields implicitly.
#'   Version 2 starts with `v2:`; legacy version 1 is an unprefixed digest.
#'   A legacy hash cannot detect changes below its original numeric precision.
#' @export
#' @examples
#' content_hash(list(b = 2, a = 1))
content_hash <- function(x, version = "2") {
  ensure(is.character(version) && length(version) == 1L && !is.na(version) && version %in% c("1", "2"), "hash.version")
  text <- canonical_json(x, digits = if (version == "1") NA else 17L)
  paste0(if (version == "2") "v2:" else "", digest::digest(text, algo = "sha256", serialize = FALSE))
}
hash_version <- function(reference) {
  ensure(scalar_text(reference) && grepl("^(v2:)?[0-9a-f]{64}$", reference), "hash.version")
  if (startsWith(reference, "v2:")) "2" else "1"
}
# Verification always follows the stored contract, never a fallback match.
hash_content <- function(x, reference) content_hash(x, version = hash_version(reference))
json <- function(x) {
  if (is.object(x) && is.list(x) && !is.data.frame(x)) x <- unclass(x)
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = 17L))
}
from_json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)

#' @importFrom stats setNames
NULL
