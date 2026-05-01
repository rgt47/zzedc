saveData <- function(data) {
  fileName <- sprintf("%s_%s.csv", as.integer(Sys.time()), digest::digest(data))
  write.csv(x = data, file = file.path("data", fileName), row.names = FALSE, quote = TRUE)
}
