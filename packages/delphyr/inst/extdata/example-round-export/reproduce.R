args <- commandArgs(trailingOnly=TRUE)
path <- if(length(args)) args[1] else '.'
result <- delphyr::reproduce_export(path)
print(result$results)
