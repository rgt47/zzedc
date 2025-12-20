#' Protocol-CRF Linkage System (Feature #25)
#'
#' Links CRF fields and forms to protocol requirements, ensuring
#' traceability between protocol objectives and data collection.
#'
#' @name protocol_linkage
#' @docType package
NULL

#' Initialize Protocol Linkage System
#' @return List with success status
#' @export
init_protocol_linkage <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS protocol_definitions (
        protocol_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_number TEXT UNIQUE NOT NULL,
        protocol_title TEXT NOT NULL,
        protocol_version TEXT DEFAULT '1.0',
        therapeutic_area TEXT,
        phase TEXT,
        sponsor TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS protocol_objectives (
        objective_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_id INTEGER NOT NULL,
        objective_type TEXT NOT NULL,
        objective_description TEXT NOT NULL,
        is_primary INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (protocol_id) REFERENCES protocol_definitions(protocol_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS protocol_crf_links (
        link_id INTEGER PRIMARY KEY AUTOINCREMENT,
        protocol_id INTEGER NOT NULL,
        objective_id INTEGER,
        crf_id INTEGER,
        form_id INTEGER,
        field_code TEXT,
        link_rationale TEXT,
        is_critical INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        FOREIGN KEY (protocol_id) REFERENCES protocol_definitions(protocol_id)
      )
    ")

    list(success = TRUE, message = "Protocol linkage system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Protocol Definition
#' @param protocol_number Unique protocol number
#' @param protocol_title Protocol title
#' @param created_by User creating
#' @param therapeutic_area Optional therapeutic area
#' @param phase Optional study phase
#' @param sponsor Optional sponsor name
#' @return List with success status
#' @export
create_protocol_definition <- function(protocol_number, protocol_title,
                                         created_by, therapeutic_area = NULL,
                                         phase = NULL, sponsor = NULL) {
  tryCatch({
    if (missing(protocol_number) || protocol_number == "") {
      return(list(success = FALSE, error = "protocol_number is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO protocol_definitions (
        protocol_number, protocol_title, therapeutic_area, phase, sponsor,
        created_by
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      protocol_number, protocol_title,
      if (is.null(therapeutic_area)) NA_character_ else therapeutic_area,
      if (is.null(phase)) NA_character_ else phase,
      if (is.null(sponsor)) NA_character_ else sponsor,
      created_by
    ))

    protocol_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, protocol_id = protocol_id,
         message = "Protocol created")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Protocol Objective
#' @param protocol_id Protocol ID
#' @param objective_type Type (PRIMARY, SECONDARY, EXPLORATORY)
#' @param objective_description Description
#' @param is_primary Whether primary objective
#' @return List with success status
#' @export
add_protocol_objective <- function(protocol_id, objective_type,
                                    objective_description, is_primary = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO protocol_objectives (
        protocol_id, objective_type, objective_description, is_primary
      ) VALUES (?, ?, ?, ?)
    ", params = list(protocol_id, objective_type, objective_description,
                     as.integer(is_primary)))

    list(success = TRUE, message = "Objective added")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Link CRF to Protocol
#' @param protocol_id Protocol ID
#' @param created_by User creating link
#' @param objective_id Optional objective ID
#' @param crf_id Optional CRF ID
#' @param form_id Optional form ID
#' @param field_code Optional field code
#' @param link_rationale Rationale for linkage
#' @param is_critical Whether critical for endpoints
#' @return List with success status
#' @export
link_crf_to_protocol <- function(protocol_id, created_by, objective_id = NULL,
                                  crf_id = NULL, form_id = NULL,
                                  field_code = NULL, link_rationale = NULL,
                                  is_critical = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO protocol_crf_links (
        protocol_id, objective_id, crf_id, form_id, field_code,
        link_rationale, is_critical, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      protocol_id,
      if (is.null(objective_id)) NA_integer_ else as.integer(objective_id),
      if (is.null(crf_id)) NA_integer_ else as.integer(crf_id),
      if (is.null(form_id)) NA_integer_ else as.integer(form_id),
      if (is.null(field_code)) NA_character_ else field_code,
      if (is.null(link_rationale)) NA_character_ else link_rationale,
      as.integer(is_critical), created_by
    ))

    list(success = TRUE, message = "CRF linked to protocol")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Protocol Definitions
#' @param include_inactive Include inactive protocols
#' @return List with protocols
#' @export
get_protocol_definitions <- function(include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (include_inactive) {
      protocols <- DBI::dbGetQuery(con, "SELECT * FROM protocol_definitions")
    } else {
      protocols <- DBI::dbGetQuery(con, "
        SELECT * FROM protocol_definitions WHERE is_active = 1
      ")
    }

    list(success = TRUE, protocols = protocols, count = nrow(protocols))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Protocol CRF Links
#' @param protocol_id Protocol ID
#' @return List with links
#' @export
get_protocol_crf_links <- function(protocol_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    links <- DBI::dbGetQuery(con, "
      SELECT * FROM protocol_crf_links WHERE protocol_id = ?
    ", params = list(protocol_id))

    list(success = TRUE, links = links, count = nrow(links))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Protocol Linkage Statistics
#' @return List with statistics
#' @export
get_protocol_linkage_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        (SELECT COUNT(*) FROM protocol_definitions WHERE is_active = 1)
          as active_protocols,
        (SELECT COUNT(*) FROM protocol_objectives) as total_objectives,
        (SELECT COUNT(*) FROM protocol_crf_links) as total_links,
        (SELECT COUNT(*) FROM protocol_crf_links WHERE is_critical = 1)
          as critical_links
    ")

    list(success = TRUE, statistics = as.list(stats))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
