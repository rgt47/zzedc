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

# yaml is in Suggests and absent from the backend CI jobs.
if (requireNamespace('yaml', quietly = TRUE)) {
  tmpl <- yaml::yaml.load(zzedc:::clickhouse_config_template())
  expect_identical(tmpl$database$clickhouse$compression, 'none',
    info = 'generated config template sets compression none')
}
