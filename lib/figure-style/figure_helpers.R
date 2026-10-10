## figure_helpers.R — the Scio toolkit cross-language FIGURE-STYLE CONTRACT (R side).
## =====================================================================================
## ONE place that owns the project's figure format so phase viz stages never reinvent it. This
## is the R half of a two-language contract; the Python half (`figure_helpers.py`, same dir) has
## FUNCTION PARITY — identical public names, equivalent semantics — and both read the SAME
## `analysis_config.yaml:figures` block. Centralizing styling here is the load-bearing capability
## behind the owner's #1 recurring pain point (figure legibility) and #2 (results placement).
##
## UNIFIED single-variant, dual-FORMAT contract (promoted from the in-project Wave-0 prototype):
##   * project_theme()  — ONE legible theme (no print/screen variant); sizes from the `figures:`
##                        block; legible BOTH shrunk to a journal column AND projected to a room.
##   * save_figure()    — ONE themed plot -> <name>.pdf AND <name>.png (same geometry, NO
##                        .print/.screen suffix). cairo_pdf for Unicode glyphs. NEVER re-themes
##                        (the CALLER owns ALL theming). Purges stale same-stem files first.
##   * save_overview()  — figure + sibling table + README caption, atomic. Caption -> <name>.png.
##   * style_series()   — alignment-safe running-sum normalizer (`style_running_sum` alias).
##   * scale_color_okabe / scale_fill_okabe — Okabe-Ito colorblind-safe palette helpers.
## The `variant` parameter is ACCEPTED on project_theme/save_figure/set_paper_style but IGNORED
## (drop-in compat: old call sites that pass "screen"/"print"/"both" still work).
##
## Config keys read (from `analysis_config.yaml:figures`):
##   base_size, title_size, subtitle_size, axis_title_size, axis_text_size, strip_size,
##   legend_text_size, caption_size, label_size, cue_size, line_width, point_size,
##   width, height, width_wide, width_narrow, dpi, formats, top_n, volcano_label_top,
##   z_clamp, nes_cap, running_sum_ylim, running_sum_top, running_sum_heights,
##   caption_wrap_column, by_contrast_dir, overview_dir
## Plus, from elsewhere in the config: `paths.results` (results root), `paths.master`
## (master-table root), `paths.stage_tables_subdir` / `paths.stage_figures_subdir`, and
## `colors.okabe_ito` (the categorical palette).
##
## LAZY HEAVY-DEP DESIGN (important — read before editing):
##   This file MUST be `source()`-able and its path / caption / table / config functions callable
##   WITHOUT ggplot2 / cairo on a bare box. Plotting deps (ggplot2, cairo) are loaded LAZILY,
##   inside the function that needs them via requireNamespace() — never at top level — so a parity
##   check / code review on a toolchain-less box can source this file. Plotting functions degrade
##   to a clear stop() when ggplot2 is absent. There are NO top-level side effects.
##
## Reuse (one source, a few calls):
##   source("01_modules/scio/lib/figure-style/figure_helpers.R")
##   cfg <- load_figure_config("02_analysis/config/analysis_config.yaml")
##   p <- ggplot(...) + ... + project_theme(config = cfg)        # the SINGLE theme entry point
##   save_overview(p, "04_gsea", "gsea_hallmark_heatmap", table = df,
##                 finding = "Hallmark IFN-alpha/gamma dominate the ISD90 response.",
##                 script = "02_analysis/stages/11_gsea_viz.R", fn = "save_overview",
##                 config_kv = "figures.nes_cap = 3.5", input = "03_results/objects/gsea.rds",
##                 how_to_read = "Rows = pathways; color = NES (orange up / blue down).",
##                 config = cfg)            # figure + sibling table + caption, atomic

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

## Fallback FLOORS, used only when a key is absent from the project config; the project config is
## authoritative. Keep in sync with figure_helpers.py:_FIG_DEFAULTS + the config template.
.FIG_DEFAULTS <- list(
  base_size = 14, title_size = 16, subtitle_size = 11, axis_title_size = 13,
  axis_text_size = 11, strip_size = 12, legend_text_size = 11, caption_size = 9,
  label_size = 4, cue_size = 4, line_width = 1.0, point_size = 2.4,
  width = 8.5, height = 6.5, width_wide = 13, width_narrow = 6,
  dpi = 300, rasterized_dpi = 600, formats = c("pdf", "png"),
  top_n = 20, volcano_label_top = 10, z_clamp = 2.5, nes_cap = 3.5,
  running_sum_ylim = c(-1, 1), running_sum_top = 5, running_sum_heights = c(2.4, 0.7, 0.9),
  caption_wrap_column = 70,
  by_contrast_dir = "by_contrast", overview_dir = "_overview")

.DEFAULT_CONFIG_PATH <- "02_analysis/config/analysis_config.yaml"

## =====================================================================================
## 0. CONFIG — read the figures block once; everything else takes `config=` (no naked literals)
## =====================================================================================
load_figure_config <- function(path = NULL) {
  ## Load the project analysis_config.yaml and return the full parsed list. Pass it to every
  ## other function as `config=`. Reading once per stage file keeps these helpers side-effect-free.
  if (!requireNamespace("yaml", quietly = TRUE))
    stop("load_figure_config() needs the 'yaml' package to read analysis_config.yaml.")
  yaml::read_yaml(path %||% .DEFAULT_CONFIG_PATH)
}

.figures <- function(config) {
  ## Merge: project figures values over .FIG_DEFAULTS floors.
  f <- .FIG_DEFAULTS
  pf <- (config %||% list())$figures %||% list()
  modifyList(f, pf)
}

.fig_get <- function(config, key) {
  ## One figures-key lookup with default fallback (mirrors %||% on CONFIG$figures).
  .figures(config)[[key]] %||% .FIG_DEFAULTS[[key]]
}

.results_root <- function(config) {
  (config %||% list())$paths$results %||% "03_results/"
}

.master_root <- function(config) {
  (config %||% list())$paths$master %||% file.path(.results_root(config), "master")
}

.stage_dir <- function(config, stage, kind) {
  ## 03_results/<stage>/<figures|tables>/ — the one place the {figures,tables} subdir is named.
  stopifnot(kind %in% c("figures", "tables"))
  paths <- (config %||% list())$paths %||% list()
  subdir <- if (kind == "figures") (paths$stage_figures_subdir %||% "figures")
            else                   (paths$stage_tables_subdir %||% "tables")
  file.path(.results_root(config), stage, subdir)
}

## =====================================================================================
## 1. PATHS — per-contrast and cross-contrast; the ONLY sanctioned way to build these dirs
## =====================================================================================
contrast_path <- function(stage, contrast, kind = "figures", config = NULL) {
  ## Build + mkdir 03_results/<stage>/<kind>/by_contrast/<contrast>/; return the dir.
  ## kind in {"figures","tables"}. Contrast dir name MUST be the exact config contrast name.
  d <- file.path(.stage_dir(config, stage, kind), .fig_get(config, "by_contrast_dir"), contrast)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

overview_path <- function(stage, kind = "figures", config = NULL) {
  ## Build + mkdir 03_results/<stage>/<kind>/_overview/ (cross-contrast); return the dir.
  d <- file.path(.stage_dir(config, stage, kind), .fig_get(config, "overview_dir"))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.resolve_fig_dir <- function(stage, contrast, overview, config) {
  ## Pick the figures dir: by_contrast/<c>/ if `contrast` given, else _overview/ if `overview`.
  if (!is.null(contrast)) return(contrast_path(stage, contrast, "figures", config))
  if (isTRUE(overview))   return(overview_path(stage, "figures", config))
  d <- .stage_dir(config, stage, "figures")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

## =====================================================================================
## 2. THEME — the SINGLE style entry point (one unified, legible tier; no print/screen variant).
##    project_theme() is the R canonical name; set_paper_style() is the thin same-named alias so a
##    cross-language parity grep finds BOTH contract names here (the Python file likewise has both).
##    Sizes come from the `figures:` block. `variant` is accepted but IGNORED (drop-in compat with
##    old call sites that pass "screen"/"print"/"both").
## =====================================================================================
project_theme <- function(base_size = NULL, legend = TRUE, variant = NULL, config = NULL,
                          panel_spacing = NULL, ...) {
  ## Return ONE legible ggplot2 theme built from the `figures:` config (LAZY ggplot2 load). Legible
  ## BOTH shrunk to a journal column AND projected to the back of a room — there is no per-variant
  ## tier. Plain (non-bold) axis titles; bold title/legend-title/strip; decluttered minor grid;
  ## bottom/left spines only; right legend with a little inter-row air. cairo on PDF export (see
  ## save_figure) so Unicode glyphs render. stop()s with context if ggplot2 is absent.
  ## Facet panels sit `panel_spacing` lines apart: the argument, else `figures.panel_spacing_lines`,
  ## else ggplot2's default.
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("project_theme() needs ggplot2 (the plotting backend). Install ggplot2, or call only ",
         "the path/caption/table helpers (which need no backend).")
  f  <- .figures(config)
  bs <- as.numeric(base_size %||% f$base_size %||% 14)
  spacing <- panel_spacing %||% f$panel_spacing_lines
  spacing_theme <- if (is.null(spacing)) ggplot2::theme() else
    ggplot2::theme(panel.spacing = ggplot2::unit(as.numeric(spacing), "lines"))
  ggplot2::theme_minimal(base_size = bs) + spacing_theme +
    ggplot2::theme(
      text             = ggplot2::element_text(size = bs),
      plot.title       = ggplot2::element_text(size = f$title_size    %||% 16, face = "bold"),
      plot.subtitle    = ggplot2::element_text(size = f$subtitle_size %||% 11, colour = "grey25"),
      plot.caption     = ggplot2::element_text(size = f$caption_size  %||% 9,  colour = "grey45",
                                               hjust = 0, lineheight = 1.05),
      axis.title       = ggplot2::element_text(size = f$axis_title_size %||% 13),  # plain (not bold)
      axis.text        = ggplot2::element_text(size = f$axis_text_size  %||% 11),
      legend.text      = ggplot2::element_text(size = f$legend_text_size %||% 11),
      legend.title     = ggplot2::element_text(size = f$legend_text_size %||% 11, face = "bold"),
      strip.text       = ggplot2::element_text(size = f$strip_size %||% 12, face = "bold"),
      legend.key.spacing.y = ggplot2::unit(3, "pt"),     # a little air between legend rows
      legend.position  = if (isTRUE(legend)) "right" else "none",
      panel.grid.minor = ggplot2::element_blank(),       # declutter
      axis.line        = ggplot2::element_line(linewidth = 0.4),  # keep bottom/left
      panel.border     = ggplot2::element_blank(),       # no top/right box (spine removal)
      plot.title.position = "plot",
      plot.margin      = ggplot2::margin(8, 12, 8, 8))
}

set_paper_style <- function(...) {
  ## Cross-language alias of project_theme() (the Python-side canonical name). Present so a parity
  ## grep finds `set_paper_style` in BOTH files. Returns the same ggplot2 theme object. Forwards
  ## every argument (including the accepted-but-ignored `variant`).
  project_theme(...)
}

## =====================================================================================
## 3. EXPORT — ONE plot -> <name>.pdf + <name>.png, ONE geometry, ONE theme.
##    `variant` accepted but IGNORED (drop-in compat). `name` may carry a subdir (e.g.
##    "Hallmark/dotplot"); the subdir is created. Output dir resolved via .resolve_fig_dir()
##    (contrast_path/overview_path/the plain stage figures dir). NEVER re-themes — the CALLER owns
##    ALL theming (project_theme() is a COMPLETE theme; re-applying it would clobber per-figure
##    tweaks the caller added afterwards). `void = TRUE` strips axis chrome + grid AFTER theming.
## =====================================================================================
## Borderless-panel override layer: strips axis chrome + panel grid so a network graph / centred
## info panel does not leak 0–1 axes, literal x/y axis titles, and a grid. Applied only when
## save_figure(..., void = TRUE) is requested. Lazy ggplot2 (only reached from inside save_figure,
## which already guards the namespace).
.void_overlay <- function() {
  ggplot2::theme(
    axis.title   = ggplot2::element_blank(),
    axis.text    = ggplot2::element_blank(),
    axis.ticks   = ggplot2::element_blank(),
    axis.line    = ggplot2::element_blank(),
    panel.grid   = ggplot2::element_blank(),
    ## borderless-panel presentation (centred title, left-flush caption with headroom).
    plot.title   = ggplot2::element_text(hjust = 0.5, face = "bold", lineheight = 1.1),
    plot.caption = ggplot2::element_text(hjust = 0, margin = ggplot2::margin(t = 5)),
    plot.margin  = ggplot2::unit(c(0.4, 0.6, 0.7, 0.8), "cm"))
}

.fig_geom <- function(config, width, height, wide) {
  ## c(width, height) inches for the ONE shared canvas. `wide` selects width_wide; per-call
  ## width/height override. Default 8.5 x 6.5.
  f <- .figures(config)
  w <- as.numeric(width  %||% (if (isTRUE(wide)) (f$width_wide %||% 13) else (f$width %||% 8.5)))
  h <- as.numeric(height %||% (f$height %||% 6.5))
  c(w, h)
}

.purge_stem <- function(out_dir, stem) {
  ## Delete every same-stem <stem>.{png,pdf} (incl. stale .screen/.print dual-variant leftovers)
  ## under out_dir so a fresh write owns its namespace. Base R only (no plotting backend).
  if (!dir.exists(out_dir)) return(invisible(0L))
  all <- list.files(out_dir, full.names = FALSE)
  hit <- startsWith(all, paste0(stem, ".")) &
         (endsWith(all, ".png") | endsWith(all, ".pdf"))
  if (any(hit)) file.remove(file.path(out_dir, all[hit]))
  invisible(sum(hit))
}

save_figure <- function(plot, stage, name, variant = NULL, contrast = NULL,
                        overview = FALSE, config = NULL,
                        width = NULL, height = NULL, wide = FALSE, void = FALSE) {
  ## Render ONE plot object to BOTH formats from one call (LAZY ggplot2/cairo load):
  ##   <name>.pdf  — vector PDF via cairo_pdf (editable, Unicode direction glyphs render)
  ##   <name>.png  — raster PNG @ dpi
  ## Same geometry + same theme for both — NO .print/.screen suffix. `variant` is accepted for
  ## drop-in compat with old call sites but has NO effect. Output dir resolved via
  ## .resolve_fig_dir(); `name` may carry a subdir which is created. Stale same-stem files are
  ## purged first. void = TRUE strips axis chrome + grid AFTER theming (ggraph networks / info
  ## panels) WITHOUT a raw theme() in the caller. Returns a named list (format -> filepath).
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("save_figure() needs ggplot2 to render. On a backend-less box call the path/caption/",
         "table helpers instead, which need no plotting backend.")
  cfg <- config
  f   <- .figures(cfg)
  geo <- .fig_geom(cfg, width, height, wide)

  base_dir <- .resolve_fig_dir(stage, contrast, overview, cfg)
  sub  <- dirname(name); stem <- basename(name)
  out_dir <- if (identical(sub, ".")) base_dir else file.path(base_dir, sub)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  .purge_stem(out_dir, stem)

  ## Theming is entirely the CALLER's job (every viz call site already adds
  ## project_theme()/style_series()). save_figure must NOT re-theme: project_theme is a COMPLETE
  ## theme (theme_minimal base), so a second application RESETS every element the caller set AFTER
  ## their own project_theme() — plot.tag.position, legend.position="bottom", axis.text.x angle,
  ## style_series's legend pin — silently clobbering per-figure tweaks. The exporter only writes.
  styled <- plot
  if (isTRUE(void)) styled <- styled + .void_overlay()

  base_dpi   <- as.numeric(f$dpi %||% 300)
  raster_dpi <- as.numeric(f$rasterized_dpi %||% f$dpi %||% 600)
  written <- list()
  for (ext in c("pdf", "png")) {
    out <- file.path(out_dir, paste0(stem, ".", ext))
    dev <- if (identical(ext, "pdf") && isTRUE(capabilities()[["cairo"]]))
             grDevices::cairo_pdf else NULL
    ## PDF at rasterized_dpi so ggrastr-rasterised dense layers (see rasterize_axes) embed as a
    ## crisp raster while text/axes stay vector; PNG at dpi.
    out_dpi <- if (identical(ext, "pdf")) raster_dpi else base_dpi
    ggplot2::ggsave(out, styled, width = geo[1], height = geo[2],
                    dpi = out_dpi, device = dev)
    written[[ext]] <- out
  }
  message(sprintf("  [figure-style] save_figure: %s.{pdf@%g,png@%g} (%gx%gin)",
                  stem, raster_dpi, base_dpi, geo[1], geo[2]))
  invisible(written)
}

## =====================================================================================
## 3a. RASTERIZE — R analog of the Python rasterize_axes(): rasterize the dense (point-cloud)
##     LAYERS of a ggplot so they embed as a raster in the vector PDF (crisp text/axes, small
##     file) — the ggplot2 route to matplotlib's set_rasterized(TRUE) on scatter collections.
## =====================================================================================
rasterize_axes <- function(plot, dpi = NULL, config = NULL, layers = c("Point", "Sf")) {
  ## Rasterize the dense point/scatter layers of a ggplot for a small, openable vector PDF (dense
  ## UMAP/embedding overlays otherwise embed one vector glyph per cell). Uses ggrastr if available;
  ## otherwise returns `plot` unchanged with a one-time note (dense layers stay vector). `dpi`
  ## defaults to figures.rasterized_dpi. Returns the (possibly rasterised) plot.
  if (!requireNamespace("ggrastr", quietly = TRUE)) {
    message("  [figure-style] rasterize_axes(): ggrastr not installed — returning plot unchanged ",
            "(dense layers stay vector in the PDF). install.packages('ggrastr') to enable.")
    return(plot)
  }
  d <- as.numeric(dpi %||% .fig_get(config, "rasterized_dpi") %||% 600)
  ggrastr::rasterise(plot, layers = layers, dpi = d)
}

## =====================================================================================
## 3b. SERIES POST-STYLER — alignment-safe running-sum normalizer (was style_running_sum).
##    The toolkit gsea_running_sum_plot() owns panel construction AND alignment; it returns a
##    patchwork carrying a `grs_restyle` closure (the clean extension interface). We re-skin the
##    running-sum via NAMED knobs — ES y clamped to `ylim`, a SINGLE legend collected OUTSIDE on
##    the right + TOP-justified, x ticks ONLY on the bottom panel, hidden rug y-index labels,
##    project panel_heights, and project_theme as the base — WITHOUT ever indexing styled[[i]] (the
##    old desync-prone path). Non-closure + non-patchwork fallbacks are retained.
## =====================================================================================
style_series <- function(plot, ylim = NULL, config = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("style_series() needs ggplot2.")
  f    <- .figures(config)
  ylim <- as.numeric(unlist(ylim %||% (f$running_sum_ylim %||% c(-1, 1))))
  stopifnot(length(ylim) == 2, all(is.finite(ylim)))
  ph <- as.numeric(unlist(f$running_sum_heights %||% c(2.4, 0.7, 0.9)))

  ## Clean toolkit interface: re-skin via the attached composer closure (no indexing).
  restyle <- attr(plot, "grs_restyle")
  if (is.function(restyle)) {
    styled <- restyle(
      es_ylim         = ylim,                          # clamp ES y for comparability
      legend_position = "right",                       # ONE legend, outside-right
      xticks          = "bottom",                      # x ticks only on the bottom panel
      rug_ylabels     = FALSE,                          # hide rug y-index labels
      panel_heights   = ph,                             # ES : rug : metric proportions
      base_theme      = project_theme(config = config)) # project base; chrome re-asserted on top
    ## Top-align the collected outside-right legend so it sits at the level of the
    ## top (ES) panel rather than vertically centred across all three panels.
    return(styled & ggplot2::theme(
      legend.justification.right = "top",
      legend.justification       = "top"))
  }

  if (!inherits(plot, "patchwork")) {
    ## non-patchwork series figure: simple shared-y + inside legend
    styled <- tryCatch(plot + project_theme(config = config), error = function(e) plot)
    return(styled + ggplot2::coord_cartesian(ylim = ylim) +
             ggplot2::theme(legend.position = "inside",
                            legend.position.inside = c(0.98, 0.98),
                            legend.justification = c(1, 1),
                            legend.background = ggplot2::element_rect(fill = "white", colour = "grey90")))
  }

  ## Fallback: a patchwork WITHOUT the toolkit closure (e.g. a non-toolkit series figure). Theme +
  ## collect a single right legend at the figure level via `&` (no panel indexing). We deliberately
  ## do NOT clamp y here — a global `&` ylim would wrongly squash the rug/metric panels; ES clamping
  ## is the toolkit's job.
  styled <- tryCatch(plot & project_theme(config = config), error = function(e) plot)
  styled <- tryCatch(styled + patchwork::plot_layout(heights = ph, guides = "collect"),
                     error = function(e) styled)
  styled & ggplot2::theme(
    legend.position      = "right",
    legend.key.spacing.y = ggplot2::unit(3, "pt"),
    legend.background    = ggplot2::element_rect(fill = "white", colour = "grey90"),
    legend.key.size      = ggplot2::unit(0.8, "lines"))
}
## Canonical name for the same operation (so a viz stage can call either).
style_running_sum <- function(plot, ylim = NULL, config = NULL) style_series(plot, ylim = ylim, config = config)

## =====================================================================================
## 4. PURGE — delete stale figures before a fresh write so a run OWNS its figure namespace
## =====================================================================================
purge_figures <- function(stage, prefix, contrast = NULL, overview = FALSE, config = NULL) {
  ## Delete <prefix>*.{png,pdf} under the resolved stage figures dir (DC semantics). Removes
  ## orphaned stems a fresh run no longer produces. Scoped by `prefix` so stages sharing a
  ## figures/ dir don't clobber each other. Needs NO plotting backend (base R only). Returns count.
  d <- if (!is.null(contrast))
         file.path(.stage_dir(config, stage, "figures"), .fig_get(config, "by_contrast_dir"), contrast)
       else if (isTRUE(overview))
         file.path(.stage_dir(config, stage, "figures"), .fig_get(config, "overview_dir"))
       else
         .stage_dir(config, stage, "figures")
  n <- 0L
  if (dir.exists(d)) {
    ## Match by literal prefix + .png/.pdf suffix (no regex metacharacter hazards from `prefix`).
    all_files <- list.files(d, full.names = FALSE)
    hit <- startsWith(all_files, prefix) &
           (endsWith(all_files, ".png") | endsWith(all_files, ".pdf"))
    stale <- file.path(d, all_files[hit])
    if (length(stale)) { file.remove(stale); n <- length(stale) }
  }
  if (n > 0L)
    message(sprintf("  [figure-style] purge_figures('%s*'): removed %d stale file(s)", prefix, n))
  invisible(n)
}

## =====================================================================================
## 5. CAPTION — idempotent create/UPDATE of the sibling stage README.md (no plotting backend)
## =====================================================================================
write_caption <- function(stage, filename, finding, script, fn, config_kv, input,
                          how_to_read, config = NULL) {
  ## Idempotently write/replace ONE artifact's caption section in 03_results/<stage>/README.md.
  ## The section is a path-qualified heading (## figures/_overview/<file> etc.), a one-sentence
  ## FINDING, a mandatory **How to read** subsection (glyphs / sign convention / claim tier), and
  ## a `Script | Function | Config | Input` table. Re-running with the SAME `filename` REPLACES
  ## that file's section in place (idempotent — never duplicates). Prose wrapped to
  ## caption_wrap_column. Needs NO plotting backend (base R only).
  readme <- file.path(.results_root(config), stage, "README.md")
  dir.create(dirname(readme), recursive = TRUE, showWarnings = FALSE)
  wrap    <- as.integer(.fig_get(config, "caption_wrap_column"))
  heading <- sprintf("## %s", filename)
  section <- .render_caption_section(heading, finding, script, fn, config_kv, input, how_to_read, wrap)

  if (file.exists(readme)) {
    existing <- readLines(readme, warn = FALSE)
    new_text <- .replace_section(existing, heading, section)
  } else {
    new_text <- c(sprintf("# %s: artifact captions", stage), "", section)
  }
  writeLines(new_text, readme)
  invisible(readme)
}

.wrap <- function(text, width) {
  if (is.null(text) || !nzchar(as.character(text))) return("")
  paste(strwrap(as.character(text), width = width), collapse = "\n")
}

.render_caption_section <- function(heading, finding, script, fn, config_kv, input, how_to_read, wrap) {
  ## Render the canonical caption section block for one artifact (a character vector of lines).
  c(heading,
    "",
    .wrap(finding, wrap),
    "",
    paste0("**How to read:** ", .wrap(how_to_read, wrap)),
    "",
    "| Script | Function | Config | Input |",
    "|---|---|---|---|",
    sprintf("| `%s` | `%s` | `%s` | `%s` |", script, fn, config_kv, input),
    "")
}

.replace_section <- function(lines, heading, new_section) {
  ## Replace the `## <heading>` section in `lines` with `new_section`; append if absent. A section
  ## runs from its `## ` heading to the next `## `/`# ` heading or EOF. Exact heading match.
  out <- character(0)
  i <- 1L; n <- length(lines); replaced <- FALSE
  while (i <= n) {
    if (identical(trimws(lines[i]), trimws(heading))) {
      i <- i + 1L
      while (i <= n && !grepl("^## ", lines[i]) && !grepl("^# ", lines[i])) i <- i + 1L
      out <- c(out, new_section)
      replaced <- TRUE
      next
    }
    out <- c(out, lines[i]); i <- i + 1L
  }
  if (!replaced) out <- c(out, "", new_section)
  ## Trim trailing blank lines to a single terminator.
  while (length(out) && !nzchar(out[length(out)])) out <- out[-length(out)]
  c(out, "")
}

## =====================================================================================
## 6. OVERVIEW — the ATOMIC adjacency mechanism: figure + sibling table + caption in ONE call
## =====================================================================================
save_overview <- function(plot, stage, name, table, finding, script, fn, config_kv, input,
                          how_to_read, contrast = NULL, config = NULL,
                          width = NULL, height = NULL, wide = FALSE, void = FALSE) {
  ## Write a figure AND its same-stem source table AND its README caption in one call. The only
  ## sanctioned path for an overview/by-contrast figure: you cannot make the figure without its
  ## neighbor table + caption (source-table-adjacency + README-adjacency contracts, enforced
  ## mechanically). Writes:
  ##   figures/_overview/<name>.{pdf,png}   (via save_figure; or by_contrast/<c>/ if contrast)
  ##   tables/_overview/<name>.csv          (data behind the figure; round_numeric_cols)
  ##   03_results/<stage>/README.md caption (via write_caption, keyed on <name>.png, idempotent)
  ## Returns list(figures = <named list>, table = <path>, readme = <path>).
  overview <- is.null(contrast)
  figs <- save_figure(plot, stage, name, contrast = contrast, overview = overview,
                      config = config, width = width, height = height, wide = wide, void = void)
  bcd <- .fig_get(config, "by_contrast_dir")
  ovd <- .fig_get(config, "overview_dir")
  if (!is.null(contrast)) {
    tdir    <- contrast_path(stage, contrast, "tables", config)
    rel_sub <- file.path("tables", bcd, contrast)
    fig_rel <- file.path("figures", bcd, contrast, sprintf("%s.png", name))
  } else {
    tdir    <- overview_path(stage, "tables", config)
    rel_sub <- file.path("tables", ovd)
    fig_rel <- file.path("figures", ovd, sprintf("%s.png", name))
  }
  table_path <- file.path(tdir, sprintf("%s.csv", basename(name)))
  if (!is.null(table)) utils::write.csv(round_numeric_cols(table), table_path, row.names = FALSE)
  readme <- write_caption(stage, fig_rel, finding = finding, script = script, fn = fn,
                          config_kv = config_kv, input = input, how_to_read = how_to_read,
                          config = config)
  message(sprintf("  [figure-style] save_overview: figure + %s/%s.csv + README caption",
                  rel_sub, basename(name)))
  invisible(list(figures = figs, table = table_path, readme = readme))
}

## =====================================================================================
## 7. MASTER TABLE — idempotent, byte-stable cross-stage accumulator append (no plotting backend)
## =====================================================================================
append_master_table <- function(df_or_rows, database, stage, name, config = NULL) {
  ## Idempotently append rows to 03_results/master/<name>.csv, deduped on the `database` column.
  ## Re-running for the SAME `database` REPLACES those rows (filter-out then append), so the master
  ## table is a stable accumulator across stages. round_numeric_cols(sig=9) is applied for
  ## byte-stability (re-runs produce identical files). Accepts a data.frame OR a list-of-lists
  ## (rows). Needs NO plotting backend. `stage` is recorded in a `stage` column for provenance.
  df <- .to_df(df_or_rows)
  if (is.null(df[["database"]]) || !"database" %in% names(df)) df[["database"]] <- database
  df[["database"]][is.na(df[["database"]]) | df[["database"]] == ""] <- database
  if (!"stage" %in% names(df)) df[["stage"]] <- stage
  df <- round_numeric_cols(df)

  out <- file.path(.master_root(config), sprintf("%s.csv", name))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

  if (file.exists(out)) {
    existing <- utils::read.csv(out, stringsAsFactors = FALSE, check.names = FALSE)
    kept <- existing[as.character(existing[["database"]]) != as.character(database), , drop = FALSE]
    ## Union the columns so old + new schemas coexist (stable order: existing first).
    all_cols <- union(names(kept), names(df))
    for (c0 in setdiff(all_cols, names(kept))) kept[[c0]]   <- NA
    for (c0 in setdiff(all_cols, names(df)))   df[[c0]]     <- NA
    combined <- rbind(kept[, all_cols, drop = FALSE], df[, all_cols, drop = FALSE])
  } else {
    combined <- df
  }
  utils::write.csv(combined, out, row.names = FALSE)
  invisible(out)
}

## =====================================================================================
## 8. ROUNDING — round every numeric column to `sig` significant digits (byte-stable outputs)
## =====================================================================================
round_numeric_cols <- function(df_or_rows, sig = 9) {
  ## Round all numeric columns to `sig` significant digits for byte-stable re-runs. Accepts a
  ## data.frame or a list-of-lists (rows); returns a data.frame. Non-numeric columns pass through.
  ## Needs NO plotting backend.
  df <- .to_df(df_or_rows)
  for (col in names(df)) {
    if (is.numeric(df[[col]])) df[[col]] <- signif(df[[col]], sig)
  }
  df
}

## =====================================================================================
## 9. DIRECTION CUE — map a sign to an unambiguous glyph/label (avoid a bare `*`); port of 14839
## =====================================================================================
direction_cue <- function(value) {
  ## Map a signed value to an unambiguous directional glyph/label (never a bare `*`). Positive ->
  ## "up" cue; negative -> "down" cue; zero / non-finite / non-numeric -> neutral. Glyphs are
  ## arrows + words so the cue is unambiguous in both color-blind and grayscale views.
  v <- suppressWarnings(as.numeric(value[1]))
  if (is.na(v)) return("· n/a")
  if (!is.finite(v) || v == 0) return("· n.s.")
  if (v > 0) "↑ up" else "↓ down"
}

## =====================================================================================
## 10. PALETTE — Okabe-Ito colorblind-safe scales sourced from `colors.okabe_ito` (semantic keys).
##     Fall back to the canonical 8-colour Okabe-Ito palette when the config carries no colors.
## =====================================================================================
.OKABE_ITO_DEFAULT <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442",
                        "#0072B2", "#D55E00", "#CC79A7", "#000000")

.okabe <- function(config = NULL) {
  oi <- (config %||% list())$colors$okabe_ito %||% list()
  vals <- unname(unlist(oi))
  if (length(vals) == 0) .OKABE_ITO_DEFAULT else vals
}
scale_color_okabe <- function(..., config = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("scale_color_okabe() needs ggplot2.")
  ggplot2::scale_color_manual(values = .okabe(config), ...)
}
scale_fill_okabe <- function(..., config = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("scale_fill_okabe() needs ggplot2.")
  ggplot2::scale_fill_manual(values = .okabe(config), ...)
}

## =====================================================================================
## Internal converter — keep the public API data.frame-or-rows agnostic
## =====================================================================================
.to_df <- function(df_or_rows) {
  ## Normalize input to a data.frame. Accepts a data.frame or a list of named row lists.
  if (is.null(df_or_rows)) return(data.frame())
  if (is.data.frame(df_or_rows)) return(df_or_rows)
  if (is.list(df_or_rows) && length(df_or_rows) && is.list(df_or_rows[[1]])) {
    ## list-of-rows -> data.frame
    cols <- unique(unlist(lapply(df_or_rows, names)))
    cells <- lapply(cols, function(k) sapply(df_or_rows, function(r) {
      v <- r[[k]]; if (is.null(v)) NA else v
    }))
    names(cells) <- cols
    return(as.data.frame(cells, stringsAsFactors = FALSE, check.names = FALSE))
  }
  as.data.frame(df_or_rows, stringsAsFactors = FALSE, check.names = FALSE)
}
