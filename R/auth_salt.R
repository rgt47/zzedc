#' Resolve the Password Salt
#'
#' The single rule for the salt used to hash user passwords. Every code
#' path that creates a password hash or checks one uses it, so that a
#' password set in one place can be checked in another.
#'
#' @param cfg Optional application configuration (`config::get()`).
#'   When supplied, the salt is the value of the environment variable
#'   named by `cfg$auth$salt_env_var`, if that variable is set and
#'   non-empty, otherwise `cfg$auth$default_salt`, otherwise `""`. This
#'   is the rule the application's login has always applied.
#'
#' @return Character scalar.
#'
#' @details
#' When `cfg` is `NULL`: the `zzedc.auth_salt` option, which the
#' application sets at startup from its own configuration (so package
#' modules running inside it, such as user management, agree with the
#' login); otherwise, outside the application, the `ZZEDC_SALT`
#' environment variable, or `"default_salt"`, which is what the user
#' management functions used before 2026-11-11.
#'
#' Before 2026-11-11 there were several rules. The launcher's default
#' administrator was hashed with the package's built-in salt, the login
#' used the configuration's rule above, and the Admin tab's user
#' creation and password reset used `ZZEDC_SALT` or `"default_salt"`.
#' Accounts created by one path could therefore fail to log in through
#' another: the default administrator whenever `ZZEDC_SALT` was set, and
#' users created in the Admin tab whenever the configuration named no
#' salt variable.
#'
#' @examples
#' resolve_auth_salt(list(auth = list(default_salt = "abc")))
#'
#' @export
resolve_auth_salt <- function(cfg = NULL) {
  if (!is.null(cfg)) {
    env_var <- cfg$auth$salt_env_var
    salt <- if (is.character(env_var) && length(env_var) == 1 && nzchar(env_var)) {
      Sys.getenv(env_var)
    } else {
      ""
    }
    if (!nzchar(salt)) {
      salt <- cfg$auth$default_salt %||% ""
    }
    return(as.character(salt))
  }
  option_salt <- getOption("zzedc.auth_salt")
  if (!is.null(option_salt)) {
    return(option_salt)
  }
  env_salt <- Sys.getenv("ZZEDC_SALT")
  if (nzchar(env_salt)) env_salt else "default_salt"
}
