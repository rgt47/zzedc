renderPanel <- function(fields) {
  lapply(fields, function(field) {
    textInput(field, field)
  })
}
