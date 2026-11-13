# rgtlab-style tile theme
#
# A small, reusable CSS block matching the card/tile design used on
# rgtlab.org (the maintainer's own lab site, source at
# ~/prj/web/rgtlab) -- navy/gold UC San Diego identity, Newsreader
# serif headings, Public Sans body text, cream page background.
# Ported from that site's index.html (the ".research-card"/".r-ico"
# rules) rather than approximated from a screenshot, so the colors,
# font stacks, and spacing below are exact matches, not guesses.
#
# Shared by the Lab landing page (R/lab_launcher.R) and each study's
# own Home tab (inst/app/home.R), both of which call
# .rgtlab_tile_styles() the same way other internal UI helpers in
# this package are reused from inst/app/ scripts (zzedc:::).

#' CSS for rgtlab-style tiles
#'
#' A `tags$style()` block defining the `.rgtlab-tile`/`.rgtlab-ico`
#' card look (and the `--rgt-*` custom properties it depends on), for
#' inclusion in a page's `tags$head()`.
#'
#' @return A `shiny::tags$style()` object.
#' @keywords internal
.rgtlab_tile_styles <- function() {
  shiny::tags$style(shiny::HTML("
    @import url('https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;0,6..72,600;1,6..72,400;1,6..72,500&family=Public+Sans:wght@400;500;600;700&display=swap');

    :root{
      --rgt-navy:#182B49; --rgt-navy-2:#1f3a63;
      --rgt-gold:#FFCD00; --rgt-gold-text:#7A5000;
      --rgt-paper:#FBFAF6; --rgt-ink:#1c2733; --rgt-muted:#5b6573; --rgt-line:#e3e0d6;
      --rgt-serif:'Newsreader',Georgia,serif;
      --rgt-sans:'Public Sans',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    }

    .rgtlab-page-bg{ background:var(--rgt-paper); font-family:var(--rgt-sans); }
    .rgtlab-heading{
      font-family:var(--rgt-serif); font-weight:600; color:var(--rgt-navy);
    }
    .rgtlab-intro{ color:var(--rgt-muted); font-family:var(--rgt-sans); }

    .rgtlab-tile{
      display:block; background:#fff; border:1px solid var(--rgt-line);
      border-radius:4px; padding:28px 24px; text-decoration:none; color:inherit;
      font-family:var(--rgt-sans);
      transition:transform .22s,box-shadow .22s,border-color .22s;
    }
    .rgtlab-tile:hover{
      transform:translateY(-4px); box-shadow:0 16px 40px rgba(24,43,73,.10);
      border-color:#d8d4c6; text-decoration:none; color:inherit;
    }
    .rgtlab-ico{
      width:44px; height:44px; border-radius:50%; background:var(--rgt-navy);
      color:var(--rgt-gold); display:flex; align-items:center; justify-content:center;
      font-family:var(--rgt-serif); font-style:italic; font-weight:600; font-size:1.3rem;
      margin-bottom:18px;
    }
    .rgtlab-tile h3, .rgtlab-tile h4, .rgtlab-tile h6, .rgtlab-tile .rgtlab-title{
      font-family:var(--rgt-serif); font-weight:600; font-size:1.15rem;
      color:var(--rgt-navy); margin-bottom:8px; line-height:1.2;
    }
    .rgtlab-tile p, .rgtlab-tile .rgtlab-desc{
      color:var(--rgt-muted); font-size:.92rem; margin-bottom:0;
    }
    .rgtlab-meta{ color:var(--rgt-gold-text); font-size:.78rem; font-weight:600; }

    .btn-rgt-primary{
      background:var(--rgt-navy); color:#fff; border:1px solid var(--rgt-navy);
    }
    .btn-rgt-primary:hover{ background:var(--rgt-navy-2); color:#fff; }
    .btn-rgt-ghost{
      background:transparent; color:var(--rgt-navy); border:1.5px solid var(--rgt-navy);
    }
    .btn-rgt-ghost:hover{ background:var(--rgt-navy); color:#fff; }
  "))
}

#' CSS for rgtlab-style navbar/page chrome
#'
#' Ported from the same source as [.rgtlab_tile_styles()] (the
#' Quarto site's `custom.scss`: the `.navbar`/`nav.topnav` rules, and
#' `index.html`'s top navy/gold hairline). Meant for a study app's
#' own page shell (`inst/app/ui.R`, `inst/app/gsheets_ui_integration.R`)
#' alongside a `bslib::bs_theme()` already set to the same
#' navy/gold/cream palette -- this covers what theme variables alone
#' cannot (the frosted-glass navbar, the uppercase nav-link treatment,
#' the top hairline stripe), while `bs_theme()` covers the rest
#' (button colors, link colors, form control colors) so every other
#' tab's Bootstrap-class content re-skins without per-tab edits.
#'
#' @return A `shiny::tags$style()` object.
#' @keywords internal
.rgtlab_chrome_styles <- function() {
  shiny::tags$style(shiny::HTML("
    body{
      position:relative; background:var(--rgt-paper); color:var(--rgt-ink);
      font-family:var(--rgt-sans);
    }
    body::before{
      content:''; position:fixed; top:0; left:0; right:0; height:4px;
      background:linear-gradient(90deg,var(--rgt-navy) 0,var(--rgt-navy) 60%,
                                        var(--rgt-gold) 60%,var(--rgt-gold) 100%);
      z-index:1031;
    }
    .navbar{
      border-bottom:1px solid var(--rgt-line) !important;
      background-color:rgba(251,250,246,.92) !important;
      backdrop-filter:saturate(180%) blur(10px);
      -webkit-backdrop-filter:saturate(180%) blur(10px);
      box-shadow:none !important;
    }
    .navbar-brand{
      font-family:var(--rgt-serif) !important; font-weight:600 !important;
      color:var(--rgt-navy) !important; letter-spacing:.2px;
    }
    .navbar .nav-link{
      font-size:.82rem; font-weight:600; letter-spacing:.05em;
      text-transform:uppercase; color:var(--rgt-muted) !important;
      transition:color .2s;
    }
    .navbar .nav-link:hover, .navbar .nav-link.active, .navbar .show > .nav-link{
      color:var(--rgt-navy) !important;
    }
    h1, h2, h3, h4, h5, h6{ font-family:var(--rgt-serif); color:var(--rgt-navy); }
    .card, .well{ border-color:var(--rgt-line) !important; border-radius:4px !important; }
    .card-header{ font-family:var(--rgt-serif); color:var(--rgt-navy); }
  "))
}
