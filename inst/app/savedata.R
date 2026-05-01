saveData <- function(data) {
  # Ensure data directory exists
  if (!dir.exists("data")) {
    dir.create("data", recursive = TRUE)
  }
  
  # Create filename with timestamp and hash
  fileName <- sprintf("%s_%s.csv", as.integer(Sys.time()), digest::digest(data))
  
  # Write data to CSV file
  write.csv(x = data, file = file.path("data", fileName), row.names = FALSE, quote = TRUE)
  
  # Return the filename for confirmation
  return(fileName)
}

saveDataJSON <- function(data) {
  # Ensure data directory exists
  if (!dir.exists("data")) {
    dir.create("data", recursive = TRUE)
  }
  
  # Create filename with timestamp and hash
  fileName <- sprintf("%s_%s.json", as.integer(Sys.time()), digest::digest(data))
  
  # Write data to JSON file
  jsonlite::write_json(data, file.path("data", fileName), pretty = TRUE)
  
  # Return the filename for confirmation
  return(fileName)
}