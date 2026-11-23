library(tinytest)

# RClickhouse's own compression default, 'lz4', fails against current
# ClickHouse servers (verified on 26.10: 'unsupported compression
# method 144'), so the adapter must pass compression explicitly. These
# tests need neither a ClickHouse server nor RClickhouse installed.

args_fn <- zzedc:::rclickhouse_connect_args

ch <- list(host = 'chhost', database = 'zzedc_test',
           password = 'pw')
a <- args_fn(ch)

expect_identical(a$compression, 'none',
  info = 'compression defaults to none, not RClickhouse lz4')
expect_identical(a$dbname, 'zzedc_test',
  info = 'database passed as dbname, not the deprecated db')
expect_false('db' %in% names(a),
  info = 'deprecated db argument no longer passed')
expect_identical(a$port, 9000L,
  info = 'native-protocol port default unchanged')
expect_identical(a$user, 'default', info = 'user default unchanged')
expect_identical(a$password, 'pw', info = 'password passed through')

expect_identical(
  args_fn(c(ch, list(compression = 'lz4')))$compression, 'lz4',
  info = 'explicit lz4 is honored'
)
expect_error(args_fn(c(ch, list(compression = 'zstd'))),
  pattern = 'none.*lz4',
  info = 'unsupported compression rejected with a clear message')
expect_error(args_fn(c(ch, list(compression = c('none', 'lz4')))),
  info = 'compression must be a single value')

cfg <- zzedc::default_db_config('clickhouse')
expect_identical(cfg$clickhouse$compression, 'none',
  info = 'default_db_config() sets compression none')
expect_silent(
  cfg_lz4 <- zzedc::default_db_config('clickhouse', compression = 'lz4'),
  info = 'compression is a recognized default_db_config() override'
)
expect_identical(cfg_lz4$clickhouse$compression, 'lz4',
  info = 'default_db_config() compression override honored')

# RClickhouse speaks the native TCP protocol (port 9000); a default of
# the HTTP port (8123) made every default config fail to connect.
expect_identical(cfg$clickhouse$port, 9000L,
  info = 'default_db_config() defaults to the native port')
expect_identical(args_fn(cfg$clickhouse)$port, 9000L,
  info = 'default config reaches RClickhouse with the native port')
expect_identical(
  zzedc:::build_adapter_config('clickhouse',
    server_config = list(database = 'zzedc'))$clickhouse$port,
  9000L,
  info = 'setup wizard config defaults to the native port'
)
expect_identical(
  zzedc::default_db_config('clickhouse', port = 9440L)$clickhouse$port,
  9440L,
  info = 'explicit port override honored'
)

# yaml is in Suggests and absent from the backend CI jobs.
if (requireNamespace('yaml', quietly = TRUE)) {
  tmpl <- yaml::yaml.load(zzedc:::clickhouse_config_template())
  expect_identical(tmpl$database$clickhouse$compression, 'none',
    info = 'generated config template sets compression none')
  expect_identical(tmpl$database$clickhouse$port, 9000L,
    info = 'generated config template uses the native port')
}

# ----------------------------------------------------------------------
# Parameter interpolation. RClickhouse binds no parameters, so the
# adapter interpolates them; DBI::ANSI() stands in for a connection.
# ----------------------------------------------------------------------

interp <- zzedc:::clickhouse_interpolate
ansi <- DBI::ANSI()

expect_identical(interp(ansi, 'SELECT 1', NULL), 'SELECT 1',
  info = 'NULL params leave SQL unchanged')
expect_identical(interp(ansi, 'SELECT 1', list()), 'SELECT 1',
  info = 'empty params leave SQL unchanged')
expect_identical(
  interp(ansi, 'INSERT INTO t VALUES (?, ?)', list('a', 2L)),
  "INSERT INTO t VALUES ('a', 2)",
  info = 'positional ? placeholders are filled in order'
)
expect_identical(
  interp(ansi, 'SELECT * FROM t WHERE u = ?', c('x')),
  "SELECT * FROM t WHERE u = 'x'",
  info = 'atomic vector params accepted'
)
expect_identical(
  interp(ansi, "SELECT '?' AS q, ? AS a", list('v')),
  "SELECT '?' AS q, 'v' AS a",
  info = '? inside a string literal is not a placeholder'
)
expect_identical(
  interp(ansi, 'SELECT ?', list("O'Brien")),
  "SELECT 'O''Brien'",
  info = 'values are quoted by the connection, not pasted raw'
)
expect_error(interp(ansi, 'SELECT ?, ?', list('only one')),
  info = 'placeholder/value count mismatch is an error')

expect_identical(
  zzedc:::with_clickhouse_conn('plain-conn', function(con) con),
  'plain-conn',
  info = 'a non-pool connection is passed through unchanged'
)
