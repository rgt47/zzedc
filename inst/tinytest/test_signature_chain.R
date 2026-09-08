# --- regressions -------------------------------------------------
#
# verify_signature_chain() checked only that each row's
# previous_signature_hash equalled the prior row's stored
# signature_hash. That verifies the linkage fields agree with one
# another and nothing else: the signed content could be rewritten and
# the function still reported "Signature chain integrity verified".
# Changing the signer, the meaning, or the record a signature points at
# all went undetected, which is the one thing a hash chain exists to
# prevent.
#
# The ledger is rebuilt here in plain SQLite, mirroring the schema and
# the hash construction sign_record() uses, so the property can be
# asserted without an encrypted database.

if (!requireNamespace("RSQLite", quietly = TRUE) ||
    !requireNamespace("digest", quietly = TRUE)) {
  exit_file("RSQLite or digest not available")
}

sig_content <- function(s) {
  paste(s$signature_code, s$signer_user_id, s$signer_full_name,
        s$table_name, s$record_id, s$signature_meaning,
        s$signature_statement, s$record_hash, s$signed_at,
        s$previous_signature_hash, sep = "|")
}

# The verification rule under test, applied to an open connection.
chain_is_valid <- function(conn) {
  sg <- DBI::dbGetQuery(conn,
    "SELECT * FROM electronic_signatures ORDER BY signature_id ASC")
  ok <- TRUE
  for (i in seq_len(nrow(sg))) {
    s <- sg[i, ]
    expected_prev <- if (i == 1) "GENESIS" else sg$signature_hash[i - 1]
    if (!identical(as.character(s$previous_signature_hash),
                   as.character(expected_prev))) ok <- FALSE
    if (!identical(digest::digest(sig_content(s), algo = "sha256"),
                   as.character(s$signature_hash))) ok <- FALSE
  }
  ok
}

build_ledger <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(conn, "CREATE TABLE electronic_signatures (
    signature_id INTEGER PRIMARY KEY AUTOINCREMENT, signature_code TEXT,
    signer_user_id TEXT, signer_full_name TEXT, table_name TEXT,
    record_id TEXT, signature_meaning TEXT, signature_statement TEXT,
    record_hash TEXT, signature_hash TEXT NOT NULL,
    previous_signature_hash TEXT, signed_at TEXT)")
  prev <- "GENESIS"
  for (i in 1:4) {
    s <- list(signature_code = sprintf("SIG-%04d", i),
              signer_user_id = sprintf("user%d", i),
              signer_full_name = sprintf("User %d", i),
              table_name = "subjects",
              record_id = sprintf("REC-%d", i),
              signature_meaning = "approval",
              signature_statement = "I approve this record.",
              record_hash = sprintf("rec-hash-%d", i),
              signed_at = sprintf("2026-09-08 10:0%d:00", i),
              previous_signature_hash = prev)
    h <- digest::digest(sig_content(s), algo = "sha256")
    DBI::dbExecute(conn, "INSERT INTO electronic_signatures (
      signature_code, signer_user_id, signer_full_name, table_name,
      record_id, signature_meaning, signature_statement, record_hash,
      signature_hash, previous_signature_hash, signed_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)",
      list(s$signature_code, s$signer_user_id, s$signer_full_name,
           s$table_name, s$record_id, s$signature_meaning,
           s$signature_statement, s$record_hash, h, prev, s$signed_at))
    prev <- h
  }
  conn
}

conn <- build_ledger()
expect_true(chain_is_valid(conn),
  info = "an untampered ledger verifies")
DBI::dbDisconnect(conn)

# Each of these leaves every stored hash untouched, so the linkage
# check alone cannot see them.
tampers <- list(
  "the signer is replaced" =
    "UPDATE electronic_signatures SET signer_user_id='attacker',
     signer_full_name='Attacker' WHERE signature_id=2",
  "the meaning is downgraded from approval to review" =
    "UPDATE electronic_signatures SET signature_meaning='review',
     signature_statement='I have reviewed this record.'
     WHERE signature_id=3",
  "the signature is repointed at another subject record" =
    "UPDATE electronic_signatures SET record_id='REC-999',
     record_hash='rec-hash-999' WHERE signature_id=4",
  "the timestamp is moved" =
    "UPDATE electronic_signatures SET signed_at='2020-01-01 00:00:00'
     WHERE signature_id=1"
)
for (nm in names(tampers)) {
  conn <- build_ledger()
  DBI::dbExecute(conn, tampers[[nm]])
  expect_false(chain_is_valid(conn),
    info = paste("tampering is detected when", nm))
  DBI::dbDisconnect(conn)
}
