#' Subjects, Sites, and Enrollment
#'
#' Each subject's site is recorded once, at enrollment, and changed
#' only by an audited transfer; it is never inferred later from who
#' entered the data. Enrollment is a subject's first data entry
#' (design document Section 13, decision 9): the first saved form for
#' a new subject ID creates the `subjects` row, with its site, in the
#' same transaction as the entry and its audit record.
#'
#' The site recorded at enrollment is, in order: the site passed by
#' the caller (the data-entry form asks when the user has no site);
#' the entering user's `edc_users.site_id`; the study's only site;
#' a default site created for a study with none. A study with several
#' sites and a user with none records no site, which the form
#' prevents and [transfer_subject_site()] can set later.
#'
#' @name subject_enrollment
#' @keywords internal
NULL


.default_study_id <- "_default_study_"
.default_site_id <- "_default_site_"


#' Create or Migrate the `subjects` Table (internal)
#'
#' Creates `subjects` if it is missing. On an existing table (any of
#' the package's four historical definitions) it adds `site_id` and
#' `created_by` when absent, so foreign keys that other tables hold on
#' `subjects` are kept.
#'
#' @param conn A DBI connection or pool.
#' @return Invisible `NULL`.
#' @keywords internal
ensure_subjects_table <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS subjects (
      subject_id VARCHAR(64) PRIMARY KEY,
      study_id VARCHAR(64),
      site_id VARCHAR(64),
      enrollment_date TIMESTAMP,
      status TEXT,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by TEXT
    )
  ")
  fields <- DBI::dbListFields(conn, "subjects")
  if (!"site_id" %in% fields) {
    DBI::dbExecute(conn, "ALTER TABLE subjects ADD COLUMN site_id VARCHAR(64)")
  }
  if (!"created_by" %in% fields) {
    DBI::dbExecute(conn, "ALTER TABLE subjects ADD COLUMN created_by TEXT")
  }
  invisible(NULL)
}


#' Create the `sites` Table (internal)
#'
#' @param conn A DBI connection or pool.
#' @return Invisible `NULL`.
#' @keywords internal
ensure_sites_table <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS sites (
      site_id VARCHAR(64) PRIMARY KEY,
      site_name TEXT,
      active INTEGER DEFAULT 1,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by TEXT
    )
  ")
  invisible(NULL)
}


.site_exists <- function(conn, site_id) {
  DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM sites WHERE site_id = ?",
                  params = list(as.character(site_id)))$n[1] > 0
}


.insert_site <- function(conn, site_id, site_name, user_id, reason) {
  DBI::dbExecute(conn,
    "INSERT INTO sites (site_id, site_name, active, created_by)
     VALUES (?, ?, 1, ?)",
    params = list(as.character(site_id), as.character(site_name),
                  as.character(user_id)))
  .append_audit_record(
    conn, event_type = "INSERT", table_name = "sites", record_id = site_id,
    operation = paste0("Site ", site_id, " added (", reason, ")"),
    details = as.character(jsonlite::toJSON(
      list(site_id = site_id, site_name = site_name, reason = reason),
      auto_unbox = TRUE)),
    user_id = user_id)
}


#' The Study ID for New Subject Rows (internal)
#'
#' The same rule randomization uses (`.current_study_id()`): the first
#' `study_info` row, or `"_default_study_"`. When `study_info` exists
#' but is empty, that placeholder row is written and audited, because
#' `subjects.study_id` references `study_info` in the definitions
#' created by [initialize_encrypted_database()], and DuckDB enforces
#' the reference.
#'
#' @param conn A connection inside the caller's transaction.
#' @param user_id Who caused the write, for the audit record.
#' @return Character scalar.
#' @keywords internal
.study_id_for_subjects <- function(conn, user_id) {
  if (!DBI::dbExistsTable(conn, "study_info")) return(.default_study_id)
  row <- DBI::dbGetQuery(conn, "SELECT study_id FROM study_info LIMIT 1")
  if (nrow(row) > 0 && !is.na(row$study_id[1])) {
    return(as.character(row$study_id[1]))
  }
  DBI::dbExecute(conn,
    "INSERT INTO study_info (study_id, study_name, protocol_id)
     VALUES (?, ?, ?)",
    params = list(.default_study_id, .default_study_id, .default_study_id))
  .append_audit_record(
    conn, event_type = "CONFIG_CHANGE", table_name = "study_info",
    record_id = .default_study_id,
    operation = "Placeholder study record created for subject enrollment",
    user_id = user_id)
  .default_study_id
}


#' Resolve the Site Recorded at Enrollment (internal)
#'
#' @param conn A connection inside the caller's transaction.
#' @param created_by The entering user's username.
#' @param site_id A site chosen by the caller, or `NULL`.
#' @return A site ID, or `NA_character_` when the study has several
#'   sites and the user has none.
#' @keywords internal
.enrollment_site <- function(conn, created_by, site_id = NULL) {
  if (!is.null(site_id) && length(site_id) == 1 && !is.na(site_id) &&
      nzchar(site_id)) {
    if (!.site_exists(conn, site_id)) {
      stop("Site '", site_id, "' is not a registered site")
    }
    return(as.character(site_id))
  }
  user_site <- if (DBI::dbExistsTable(conn, "edc_users")) {
    DBI::dbGetQuery(conn, "SELECT site_id FROM edc_users WHERE username = ?",
                    params = list(as.character(created_by)))$site_id
  } else {
    character(0)
  }
  if (length(user_site) == 1 && !is.na(user_site) && nzchar(user_site)) {
    if (!.site_exists(conn, user_site)) {
      .insert_site(conn, user_site, user_site, created_by,
                   "the site of an enrolling user")
    }
    return(as.character(user_site))
  }
  active <- DBI::dbGetQuery(conn,
    "SELECT site_id FROM sites WHERE active = 1")$site_id
  if (length(active) == 1) return(as.character(active))
  if (length(active) == 0) {
    .insert_site(conn, .default_site_id, "Default site", created_by,
                 "single-site study")
    return(.default_site_id)
  }
  NA_character_
}


#' Sites to Offer When Enrolling a Subject (internal)
#'
#' The data-entry form asks for a site only when enrollment would
#' otherwise record none: the subject ID is new, the user has no site,
#' and the study has more than one active site. In every other case
#' the rule in [subject_enrollment] decides, and this returns `NULL`.
#'
#' @param conn A DBI connection or pool.
#' @param subject_id The subject ID being entered (`tracking_id`).
#' @param username The entering user's username.
#' @return `NULL`, or a data frame of active sites (`site_id`,
#'   `site_name`) to choose from.
#' @keywords internal
.enrollment_site_choices <- function(conn, subject_id, username) {
  if (is.null(subject_id) || length(subject_id) != 1 || is.na(subject_id) ||
      !nzchar(trimws(as.character(subject_id)))) {
    return(NULL)
  }
  if (!DBI::dbExistsTable(conn, "sites")) return(NULL)
  sites <- DBI::dbGetQuery(conn,
    "SELECT site_id, site_name FROM sites WHERE active = 1
      ORDER BY site_id")
  if (nrow(sites) <= 1) return(NULL)
  if (DBI::dbExistsTable(conn, "edc_users")) {
    user_site <- DBI::dbGetQuery(conn,
      "SELECT site_id FROM edc_users WHERE username = ?",
      params = list(as.character(username)))$site_id
    if (length(user_site) == 1 && !is.na(user_site) && nzchar(user_site)) {
      return(NULL)
    }
  }
  if (DBI::dbExistsTable(conn, "subjects")) {
    known <- DBI::dbGetQuery(conn,
      "SELECT COUNT(*) AS n FROM subjects WHERE subject_id = ?",
      params = list(as.character(subject_id)))$n[1]
    if (known > 0) return(NULL)
  }
  if (DBI::dbExistsTable(conn, "data_entries")) {
    earlier <- DBI::dbGetQuery(conn,
      "SELECT COUNT(*) AS n FROM data_entries WHERE subject_id = ?",
      params = list(as.character(subject_id)))$n[1]
    if (earlier > 0) return(NULL)
  }
  sites
}


#' Check the Site Chosen on the Form (internal)
#'
#' @inheritParams .enrollment_site_choices
#' @param chosen The value of the form's site drop-down.
#' @return `list(error = NULL, site_id = NULL)` when no choice is
#'   needed; `list(error = NULL, site_id = <chosen>)` for a valid
#'   choice; `list(error = <message>)` otherwise. `site_id` is `NULL`
#'   whenever no choice was asked for, so a value left in a hidden
#'   drop-down never overrides the user's own site.
#' @keywords internal
.enrollment_site_from_form <- function(conn, subject_id, username, chosen) {
  choices <- .enrollment_site_choices(conn, subject_id, username)
  if (is.null(choices)) return(list(error = NULL, site_id = NULL))
  if (is.null(chosen) || length(chosen) != 1 || is.na(chosen) ||
      !nzchar(chosen)) {
    return(list(error = paste("Subject", subject_id, "is new: choose the",
                              "site at which they are enrolled.")))
  }
  if (!chosen %in% choices$site_id) {
    return(list(error = paste0("'", chosen, "' is not an active site.")))
  }
  list(error = NULL, site_id = chosen)
}


#' Is This Subject's Entry Their Enrollment? (internal)
#'
#' True when the subject has neither a `subjects` row nor any earlier
#' `data_entries` row. A subject with earlier entries but no row
#' predates enrollment recording; [migrate_add_subject_sites()]
#' creates their row, with no site, for review.
#'
#' @keywords internal
.is_enrollment <- function(conn, subject_id) {
  in_subjects <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) AS n FROM subjects WHERE subject_id = ?",
    params = list(as.character(subject_id)))$n[1]
  if (in_subjects > 0) return(FALSE)
  earlier <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) AS n FROM data_entries WHERE subject_id = ?",
    params = list(as.character(subject_id)))$n[1]
  earlier == 0
}


#' Enroll a Subject (internal)
#'
#' Writes the `subjects` row and its audit record. Called inside
#' [db_insert_data_entry()]'s transaction, before the entry itself.
#'
#' @return The site recorded (possibly `NA`).
#' @keywords internal
.enroll_subject <- function(conn, subject_id, created_by, site_id = NULL,
                            ip_address = NULL, session_id = NULL) {
  site <- .enrollment_site(conn, created_by, site_id)
  study <- .study_id_for_subjects(conn, created_by)
  DBI::dbExecute(conn,
    "INSERT INTO subjects (subject_id, study_id, site_id, enrollment_date,
                           status, created_by)
     VALUES (?, ?, ?, CURRENT_TIMESTAMP, 'Enrolled', ?)",
    params = list(as.character(subject_id), study, site,
                  as.character(created_by)))
  .append_audit_record(
    conn, event_type = "INSERT", table_name = "subjects",
    record_id = subject_id,
    operation = paste0("Subject ", subject_id, " enrolled at site ",
                       if (is.na(site)) "(not recorded)" else site),
    details = as.character(jsonlite::toJSON(
      list(subject_id = subject_id, study_id = study, site_id = site,
           enrolled_by = created_by), auto_unbox = TRUE, na = "null")),
    user_id = created_by, ip_address = ip_address, session_id = session_id)
  site
}


#' Add Subjects, Sites, and Enrollment Recording to a Study Database
#'
#' Prepares an existing study for site-level monitoring:
#'
#' 1. creates `sites`, and adds `site_id` and `created_by` to
#'    `subjects` (creating it if missing);
#' 2. registers as sites the distinct non-empty `site_id` values of
#'    `edc_users` and `adverse_events`;
#' 3. creates a `subjects` row, with no site, for each subject ID in
#'    `data_entries` that has none. Their sites are not guessed: set
#'    each with [transfer_subject_site()] after review.
#'
#' Subject IDs generated by the data-entry form for forms without a
#' tracking field (`<FORM>-<14-digit timestamp>`) identify one
#' submission, not a person, and are not given a row; they are
#' returned in `skipped_generated_ids`.
#'
#' New entries need no migration: [db_insert_data_entry()] creates the
#' tables as needed and enrolls new subjects itself.
#'
#' @param conn A DBI connection.
#' @param user_id Who ran the migration, for the audit records.
#' @return A list with `success`, `sites_added`, `subjects_added`,
#'   `skipped_generated_ids`, and `subjects_without_site`; or
#'   `success = FALSE` and `error`.
#' @export
migrate_add_subject_sites <- function(conn, user_id = "migration") {
  tryCatch({
    if (any(grepl("clickhouse", class(conn), ignore.case = TRUE))) {
      stop("ClickHouse is not supported as a system of record")
    }
    ensure_subjects_table(conn)
    ensure_sites_table(conn)
    .with_db_transaction(conn, function(c) {
      existing <- function(tbl) {
        if (!DBI::dbExistsTable(c, tbl) ||
            !"site_id" %in% DBI::dbListFields(c, tbl)) {
          return(character(0))
        }
        DBI::dbGetQuery(c, sprintf(
          "SELECT DISTINCT site_id FROM %s WHERE site_id IS NOT NULL",
          tbl))$site_id
      }
      candidates <- unique(trimws(as.character(c(existing("edc_users"),
                                                   existing("adverse_events")))))
      candidates <- candidates[nzchar(candidates)]
      sites_added <- 0L
      for (s in candidates) {
        if (!.site_exists(c, s)) {
          .insert_site(c, s, s, user_id, "migration: site in use")
          sites_added <- sites_added + 1L
        }
      }

      ids <- if (DBI::dbExistsTable(c, "data_entries")) {
        DBI::dbGetQuery(c,
          "SELECT d.subject_id, MIN(d.created_date) AS first_date
             FROM data_entries d
            WHERE NOT EXISTS (SELECT 1 FROM subjects s
                               WHERE s.subject_id = d.subject_id)
            GROUP BY d.subject_id")
      } else {
        data.frame(subject_id = character(0), first_date = character(0))
      }
      generated <- grepl("^[A-Z0-9_]+-[0-9]{14}(\\.[0-9]+)?$",
                         ids$subject_id)
      todo <- ids[!generated, , drop = FALSE]
      study <- if (nrow(todo) > 0) .study_id_for_subjects(c, user_id) else NA
      for (i in seq_len(nrow(todo))) {
        sid <- as.character(todo$subject_id[i])
        DBI::dbExecute(c,
          "INSERT INTO subjects (subject_id, study_id, site_id,
                                 enrollment_date, status, created_by)
           VALUES (?, ?, NULL, ?, 'Enrolled', ?)",
          params = list(sid, study, as.character(todo$first_date[i]),
                        as.character(user_id)))
        .append_audit_record(
          c, event_type = "INSERT", table_name = "subjects", record_id = sid,
          operation = paste0("Subject ", sid,
                             " recorded by migration; site to be reviewed"),
          user_id = user_id)
      }
      unsited <- DBI::dbGetQuery(c,
        "SELECT subject_id FROM subjects WHERE site_id IS NULL")$subject_id
      list(success = TRUE, sites_added = sites_added,
           subjects_added = nrow(todo),
           skipped_generated_ids = as.character(ids$subject_id[generated]),
           subjects_without_site = as.character(unsited))
    })
  }, error = function(e) list(success = FALSE, error = conditionMessage(e)))
}


#' Register a Site
#'
#' @param conn A DBI connection.
#' @param site_id Site identifier.
#' @param site_name Display name; defaults to `site_id`.
#' @param user_id Who registered it, for the audit record.
#' @return `list(success = TRUE)`, or `success = FALSE` and `error`.
#' @export
add_site <- function(conn, site_id, site_name = site_id, user_id) {
  tryCatch({
    if (missing(site_id) || is.null(site_id) || !nzchar(trimws(site_id))) {
      stop("site_id is required")
    }
    ensure_sites_table(conn)
    .with_db_transaction(conn, function(c) {
      if (.site_exists(c, site_id)) stop("Site '", site_id, "' already exists")
      .insert_site(c, site_id, site_name, user_id, "registered")
    })
    list(success = TRUE)
  }, error = function(e) list(success = FALSE, error = conditionMessage(e)))
}


#' Record a Subject's Site, or a Transfer to Another Site
#'
#' The only way a subject's recorded site changes. Used both to set
#' the site of a subject recorded without one (after the review that
#' [migrate_add_subject_sites()] calls for) and for a transfer. The
#' previous and new site and the reason are written to the audit
#' trail in the same transaction as the change.
#'
#' @param conn A DBI connection.
#' @param subject_id The subject.
#' @param site_id A registered site.
#' @param reason Why the site is set or changed. Required.
#' @param user_id Who made the change.
#' @return `list(success = TRUE, from_site_id, site_id)`, or
#'   `success = FALSE` and `error`.
#' @export
transfer_subject_site <- function(conn, subject_id, site_id, reason,
                                  user_id) {
  tryCatch({
    if (missing(reason) || is.null(reason) || !nzchar(trimws(reason))) {
      stop("A reason is required")
    }
    .with_db_transaction(conn, function(c) {
      cur <- DBI::dbGetQuery(c,
        "SELECT site_id FROM subjects WHERE subject_id = ?",
        params = list(as.character(subject_id)))
      if (nrow(cur) == 0) stop("Subject '", subject_id, "' not found")
      if (!.site_exists(c, site_id)) {
        stop("Site '", site_id, "' is not a registered site")
      }
      from <- cur$site_id[1]
      if (identical(as.character(from), as.character(site_id))) {
        stop("Subject '", subject_id, "' is already at site '", site_id, "'")
      }
      DBI::dbExecute(c, "UPDATE subjects SET site_id = ? WHERE subject_id = ?",
                     params = list(as.character(site_id),
                                   as.character(subject_id)))
      .append_audit_record(
        c, event_type = "UPDATE", table_name = "subjects",
        record_id = subject_id,
        operation = paste0("Subject ", subject_id, " site ",
                           if (is.na(from)) "set" else "transferred",
                           " to ", site_id),
        details = as.character(jsonlite::toJSON(
          list(from_site_id = from, site_id = site_id, reason = reason),
          auto_unbox = TRUE, na = "null")),
        user_id = user_id)
      list(success = TRUE, from_site_id = from, site_id = site_id)
    })
  }, error = function(e) list(success = FALSE, error = conditionMessage(e)))
}


#' List Subjects with Their Recorded Sites
#'
#' @param conn A DBI connection.
#' @return A data frame with `subject_id`, `site_id`,
#'   `enrollment_date`, and `status`.
#' @export
subject_sites <- function(conn) {
  if (!DBI::dbExistsTable(conn, "subjects")) {
    return(data.frame(subject_id = character(0), site_id = character(0),
                      enrollment_date = character(0), status = character(0)))
  }
  ensure_subjects_table(conn)
  DBI::dbGetQuery(conn,
    "SELECT subject_id, site_id, enrollment_date, status FROM subjects
      ORDER BY subject_id")
}
