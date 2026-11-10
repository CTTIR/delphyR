args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args)) args[1] else '.'
result <- delphyr::reproduce_study_export(path)
for (round in names(result$analyses)) print(result$analyses[[round]]$decisions)
print(result$comparisons)
