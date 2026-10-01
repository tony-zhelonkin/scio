# TE GMT → clusterProfiler GSEA: Full Column Contract

> Deep-reference for the `te-geneset-gsea` skill. See `../SKILL.md` for routing, decision tree, and
> the minimal Quick Start. Come here for the exact column-name contract, annotated code walkthroughs,
> overlap-check math, class-GMT min_size guidance, and SCREAMING_SNAKE naming rules.

---

## 1. Column-Name Contract (Critical)

TE GMTs produced by `create_te_genesets()` / `export_te_genesets_gmt()` in
`TE-RNAseq-toolkit v2.0.3` use **`gs_name`** and **`gene_symbol`** as column names — NOT the
`term`/`gene` naming used by the bulk-rnaseq-gsea custom-db recipes. This distinction matters in
exactly two places:

| Operation | TE GMT (this skill) | bulk-rnaseq-gsea (gene GSEA) |
|---|---|---|
| `TERM2GENE` frame | `T2G[, .(gs_name, gene_symbol)]` | `T2G %>% rename(term=gs_name, gene=gene_symbol)` |
| `@geneSets` fix | `split(T2G$gene_symbol, T2G$gs_name)` | `split(T2G$gene, T2G$term)` |
| Overlap check | `sum(T2G$gene_symbol %in% names(ranked))` | `sum(db$T2G$gene_symbol %in% names(ranked_genes))` |

**Empty-set trap:** if you copy the bulk snippet verbatim, `T2G$gene` and `T2G$term` are `NULL`
(those columns do not exist in TE GMTs), so `@geneSets` is silently populated with empty character
vectors and `gseaplot2()` produces blank plots without an informative error.

### GMT column layout (verified `create_te_genesets.R`)

```
gs_name  \t  gs_description  \t  gene_symbol
LINE     \t  LINE elements   \t  HAL1
LINE     \t  LINE elements   \t  L1Md_T
SINE     \t  SINE elements   \t  B1_Mm
```

- `gs_name`: TE family or class identifier (e.g. `L1`, `ERVK`, `LINE`, `SINE`)
- `gene_symbol`: TE **subfamily** ID (e.g. `HAL1`, `L1Md_T`, `B1_Mm`) — the key that must match
  rownames of the ranked DE list
- `gs_description`: human-readable label; maps to `T2N` for TERM2NAME

Load with:

```r
library(data.table)
T2G <- fread(gmt_path, header = FALSE,
             col.names = c("gs_name", "gs_description", "gene_symbol"))
T2N <- unique(T2G[, .(gs_name, gs_description)])
```

---

## 2. Ranked List — ID Space

The ranked list for TE GSEA uses **TE subfamily IDs** as names (the `gene_symbol` column in the
GMT), not Ensembl gene IDs or gene symbols. Build it from rows where `is_te == TRUE` in the
combined DGEList produced by `create_combined_dge()`:

```r
# combined_dge: output of create_combined_dge() from TE-RNAseq-toolkit v2.0.3
# is_te column is added by create_combined_dge() to $genes
de_tbl <- combined_dge$table        # or limma topTable equivalent
te_idx <- combined_dge$genes$is_te  # logical vector, same length as rows

ranked <- sort(
    setNames(de_tbl$t[te_idx], rownames(de_tbl)[te_idx]),
    decreasing = TRUE
)
```

`rownames(de_tbl)[te_idx]` are the subfamily IDs because `create_combined_dge` preserves the
rownames from the TE count matrix, which come from `build_te_annotation()` using subfamily as
the primary key.

---

## 3. Overlap Check (Run Before GSEA)

```r
n_overlap <- sum(T2G$gene_symbol %in% names(ranked))
n_gmt     <- length(unique(T2G$gene_symbol))
message(sprintf("GMT overlap: %d / %d subfamily IDs (%.0f%%)",
                n_overlap, n_gmt, 100 * n_overlap / n_gmt))
stopifnot(n_overlap / n_gmt > 0.3)  # <30% -> ID space mismatch -> stop and debug
```

**If overlap is 0 or near-zero:** the ranked list was not filtered to `is_te == TRUE`, or rownames
are Ensembl gene IDs rather than subfamily IDs. Re-check that `is_te` filtering was applied and
that the count matrix passed to `create_combined_dge` had subfamily rownames for TE features.

---

## 4. Annotated GSEA Recipe

### 4a. Family-level GMT (typical case)

```r
library(clusterProfiler)
library(data.table)

# -- 1. Paths from config (never inline) -----------------------------------------
cfg      <- yaml::read_yaml("02_analysis/config/analysis_config.yaml")
proj_id  <- cfg$project$id
gmt_fam  <- file.path("03_results/objects", paste0(proj_id, "_TE_family.gmt"))

# -- 2. Load GMT ------------------------------------------------------------------
T2G <- fread(gmt_fam, header = FALSE,
             col.names = c("gs_name", "gs_description", "gene_symbol"))
T2N <- unique(T2G[, .(gs_name, gs_description)])

# -- 3. Build ranked list (TE subfamilies, sorted t-statistic) --------------------
te_idx <- combined_dge$genes$is_te
ranked <- sort(
    setNames(combined_dge$table$t[te_idx], rownames(combined_dge$table)[te_idx]),
    decreasing = TRUE
)

# -- 4. Overlap sanity check ------------------------------------------------------
n_overlap <- sum(T2G$gene_symbol %in% names(ranked))
n_gmt     <- length(unique(T2G$gene_symbol))
stopifnot(n_overlap / n_gmt > 0.3)

# -- 5. Run GSEA ------------------------------------------------------------------
gsea_fam <- clusterProfiler::GSEA(
    geneList     = ranked,
    TERM2GENE    = T2G[, .(gs_name, gene_symbol)],
    TERM2NAME    = T2N,
    pvalueCutoff = 1.0,
    minGSSize    = 5,
    maxGSSize    = 500,
    seed         = 123,
    eps          = 0
)

# -- 6. Fix @geneSets slot (REQUIRED for enrichplot) -----------------------------
# Use gs_name / gene_symbol — NOT term / gene (those columns do not exist in TE GMTs)
gsea_fam@geneSets <- split(T2G$gene_symbol, T2G$gs_name)

# -- 7. Checkpoint ----------------------------------------------------------------
saveRDS(gsea_fam, file.path("03_results/objects",
                             paste0(proj_id, "_gsea_TE_family.rds")))
```

### 4b. Class-level GMT (relaxed min_size)

The class GMT has only ~6 sets (LINE, SINE, LTR, DNA, Simple_repeat, Low_complexity). The default
`minGSSize = 5` retains larger classes but silently drops small ones; use `minGSSize = 3` to keep
all non-trivial sets.

```r
gmt_cls  <- file.path("03_results/objects", paste0(proj_id, "_TE_class.gmt"))
T2G_cls  <- fread(gmt_cls, header = FALSE,
                  col.names = c("gs_name", "gs_description", "gene_symbol"))
T2N_cls  <- unique(T2G_cls[, .(gs_name, gs_description)])

n_sets <- length(unique(T2G_cls$gs_name))
message("Class GMT sets: ", n_sets)   # expect ~6

gsea_cls <- clusterProfiler::GSEA(
    geneList     = ranked,
    TERM2GENE    = T2G_cls[, .(gs_name, gene_symbol)],
    TERM2NAME    = T2N_cls,
    pvalueCutoff = 1.0,
    minGSSize    = 3,    # relaxed from default 5 — ~6 class sets total
    maxGSSize    = 500,
    seed         = 123,
    eps          = 0
)

gsea_cls@geneSets <- split(T2G_cls$gene_symbol, T2G_cls$gs_name)
```

---

## 5. Result Normalization and SCREAMING_SNAKE Naming

When appending TE GSEA results to the master GSEA table alongside gene-pathway results, use
SCREAMING_SNAKE_CASE database prefixes to prevent name collisions:

| Level | Prefix | Example pathway ID |
|---|---|---|
| Family | `TE_FAMILY_` | `TE_FAMILY_L1` |
| Class | `TE_CLASS_` | `TE_CLASS_LINE` |

```r
normalize_te_gsea <- function(gsea_result, level = c("family", "class")) {
    level  <- match.arg(level)
    prefix <- if (level == "family") "TE_FAMILY" else "TE_CLASS"
    df     <- as.data.frame(gsea_result@result)
    df$ID          <- paste0(prefix, "_", df$ID)
    df$Description <- df$Description
    df$database    <- prefix
    # Subset to the 13-column master schema (see bulk-rnaseq-gsea references/master-tables.md)
    df
}

export_fam <- normalize_te_gsea(gsea_fam, "family")
export_cls <- normalize_te_gsea(gsea_cls, "class")
```

Idempotent append to master table:

```r
master_file <- file.path("03_results/master", "master_gsea_table.csv")
if (file.exists(master_file)) {
    master_df <- readr::read_csv(master_file, show_col_types = FALSE)
    master_df <- dplyr::filter(master_df,
                               !database %in% c("TE_FAMILY", "TE_CLASS"))
    master_df <- dplyr::bind_rows(master_df, export_fam, export_cls)
} else {
    master_df <- dplyr::bind_rows(export_fam, export_cls)
}
readr::write_csv(master_df, master_file)
```

---

## 6. Verification

```r
# Overlap check
stopifnot(sum(T2G$gene_symbol %in% names(ranked)) /
          length(unique(T2G$gene_symbol)) > 0.3)

# Non-empty result
stopifnot(nrow(gsea_fam@result) > 0)

# @geneSets populated and aligned with gene set names
stopifnot(length(gsea_fam@geneSets) == length(unique(T2G$gs_name)))
stopifnot(all(names(gsea_fam@geneSets) %in% T2G$gs_name))

# Prefix applied in normalized output
stopifnot(all(grepl("^TE_FAMILY_", export_fam$ID)))
stopifnot(all(grepl("^TE_CLASS_",  export_cls$ID)))
```

---

## 7. Source Files (TE-RNAseq-toolkit v2.0.3)

| File | Relevant exports |
|---|---|
| `R/te_utils.R` | `build_te_annotation`, `parse_te_id`, `TE_CYTOPLASMIC_CLASSES`, `TE_NUCLEAR_CLASSES` |
| `R/create_combined_dge.R` | `create_combined_dge` (adds `is_te`, `feature_type` to `$genes`) |
| `R/create_te_genesets.R` | `create_te_genesets`, `filter_te_genesets`, `export_te_genesets_gmt` |

The family GMT (`<id>_TE_family.gmt`) is produced by
`create_te_genesets(te_ann, level = "family")` then `export_te_genesets_gmt(gs_fam, path)`.
The class GMT is either produced the same way (from a cwd where the TE submodule resolves) or
built in the recipe from `class`/`subfamily` columns + the sourced constants to avoid the
`create_te_genesets(level = "class")` cwd-relative `source()` hard-error (T1b in the refactor
plan). See `te-annotation.md` for the recipe-built class T2G/T2N pattern.

---

## 8. Related References

- `../SKILL.md` — routing, Quick Start, Pitfalls, Complementary Skills
- `../../bulk-rnaseq-gsea/references/custom-databases.md` — custom gene-set providers in bulkiRNA
- `../../bulk-rnaseq-gsea/references/master-table.md` — master table via `gs_to_master()`
- `../../annotate-bulk-rnaseq-data/references/te-annotation.md` — how the GMTs and combined DGEList are produced
