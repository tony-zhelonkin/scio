# Transposable-Element Annotation (the rare case)

Annotate a transposable-element count matrix: parse TE IDs into
`Subfamily:Family:Class`, build the combined gene+TE `DGEList`, and export
family/class GMT genesets for GSEA. This is the rarer path — only datasets
carrying a TE count matrix from `star-te-preprocessing` need it.

> **Shared principle (also in SKILL.md):** Always annotate BEFORE filtering. Never
> drop low-count rows first — you lose IDs irreversibly.

## TE-ID label

TE matrix rows use the toolkit-canonical 3-field label **`Subfamily:Family:Class`**
(e.g. `L1Md_A:L1:LINE`). This is the same label `star-te-preprocessing` writes into
the SAF `GeneID`, so it parses cleanly downstream.

> **Authoritative parser:** TE-RNAseq-toolkit **v2.0.3** —
> `R/te_utils.R::parse_te_id` (version-pinned). Do not restate the parser logic here;
> the code is the spec.

## Inputs

- A TE count matrix (featureCounts on the grouped TE SAF; `Subfamily:Family:Class`
  rownames), e.g. `00_data/processed/featurecounts_TE/te_counts_matrix.txt`.
- A gene count matrix + gene annotation already produced by `gene-annotation.md`
  (provides `mat_gene`, `ann_gene_df`, and `samples` for the combined DGEList).
- Sample metadata matching the count columns (same metadata used on the gene path).

## Helpers (SSoT — do not duplicate code)

From **TE-RNAseq-toolkit v2.0.3**:

- `TE_CYTOPLASMIC_CLASSES` / `TE_NUCLEAR_CLASSES` — `R/te_utils.R` — class constants
  (`LINE`, `SINE`, `LTR`, `Retroposon` / `DNA`, `RC`)
- `parse_te_id()` — `R/te_utils.R` — authoritative `Subfamily:Family:Class` parser
- `build_te_annotation()` — `R/te_utils.R` — build annotation tibble from IDs;
  emits `feature_id, is_te, subfamily, family, class, replication_type`
- `validate_combined_input()` — `R/validate_te_input.R` — **required hard dependency**
  of `create_combined_dge()` (default `validate = TRUE`; must be sourced before calling)
- `create_combined_dge()` — `R/create_combined_dge.R` — build combined gene+TE
  `DGEList`; adds `feature_type` ("gene"/"te"), `is_te`, `subfamily`, `family`,
  `class`, `replication_type` to `$genes`; sets `$analysis_mode = "combined"`;
  TMM-normalizes
- `create_te_genesets()` — `R/create_te_genesets.R` — TERM2GENE/TERM2NAME for GSEA
  at `level = "family"` (family level has no internal `source()` and runs from any cwd)
- `export_te_genesets_gmt()` — `R/create_te_genesets.R` — write GMT file; takes the
  genesets LIST returned by `create_te_genesets()` (or a `list(T2G=, T2N=)` you build)

From **bulkiRNA** (shared with the gene path, `library(bulkiRNA)`):

- `read_counts_matrix()`, `read_metadata()`, `build_dge()`

## How-to

```r
suppressPackageStartupMessages({
  library(data.table); library(tibble); library(dplyr); library(stringr); library(yaml)
})

# ---- config (drive all paths and IDs from here) ----
cfg        <- yaml::read_yaml("02_analysis/config/analysis_config.yaml")
project_id <- cfg$project$id

outdir <- "03_results/annotated_outputs"
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

counts_te_fp  <- "00_data/processed/featurecounts_TE/te_counts_matrix.txt"

# ---- source helpers ----
library(bulkiRNA)   # read_counts_matrix(), read_metadata(), build_dge()

# TE-RNAseq-toolkit v2.0.3 — source rich R/ factories in dependency order
source("01_modules/TE-RNAseq-toolkit/R/te_utils.R")          # constants + parse_te_id + build_te_annotation
source("01_modules/TE-RNAseq-toolkit/R/validate_te_input.R") # validate_combined_input (required by create_combined_dge)
source("01_modules/TE-RNAseq-toolkit/R/create_combined_dge.R")
source("01_modules/TE-RNAseq-toolkit/R/create_te_genesets.R")

# ---- read TE counts ----
message("[info] reading TE counts...")
mat_te  <- read_counts_matrix(counts_te_fp)   # Subfamily:Family:Class rows
samples <- colnames(mat_te)

# Assume mat_gene + ann_gene_df + samples are already in scope from gene-annotation.md.
# If running standalone: source gene-annotation.md recipe first to produce mat_gene and
# the gene annotation data frame (ann_gene_df with cols Symbol, Ensembl, gene_biotype, ...).

# ---- build TE annotation (BEFORE filtering) ----
message("[info] building TE annotation...")
te_ann <- build_te_annotation(rownames(mat_te))
# te_ann columns: feature_id, is_te, subfamily, family, class, replication_type

# ---- build combined gene+TE DGEList (T2) ----
# create_combined_dge() defaults validate = TRUE → calls validate_combined_input()
# from validate_te_input.R (sourced above). Passing gene_annotation= is optional but
# recommended; te_annotation= receives the output of build_te_annotation().
# The resulting $genes slot carries: feature_type ("gene"/"te"), is_te,
# subfamily, family, class, replication_type.
# Gene subfamily slot = subfamily (gene_symbol in GSEA context).
message("[info] building combined DGEList...")
dge_combined <- create_combined_dge(
  gene_counts     = mat_gene,
  te_counts       = mat_te,
  samples         = samp_df,             # rownames = sample IDs (from gene-annotation.md)
  gene_annotation = ann_gene_df,         # optional; data.frame from gene path
  te_annotation   = build_te_annotation(rownames(mat_te))
)
saveRDS(dge_combined, file.path(outdir, paste0(project_id, "_combined_DGEList.rds")))

# ---- family GMT (T3a) ----
# level = "family" has no internal source() — runs from any cwd.
message("[info] creating family-level GMT...")
gs_fam <- create_te_genesets(te_ann, level = "family")
export_te_genesets_gmt(gs_fam, file.path(outdir, paste0(project_id, "_TE_family.gmt")))

# ---- class GMT — recipe-built (T3b, avoids T1b hard-error) ----
# create_te_genesets(te_ann, level = "class") has a hardcoded source() at
# R/create_te_genesets.R:109 that hard-errors unless cwd resolves to the project root
# that has TE-RNAseq-toolkit wired in. Build T2G/T2N from already-sourced constants instead.
message("[info] building class-level GMT (recipe-built)...")
te_only <- te_ann %>% dplyr::filter(is_te, !is.na(subfamily), !is.na(class))

T2G_class <- te_only %>%
  dplyr::distinct(gs_name = class, gene_symbol = subfamily)

T2N_class <- T2G_class %>%
  dplyr::distinct(gs_name) %>%
  dplyr::mutate(
    description = dplyr::case_when(
      gs_name %in% TE_CYTOPLASMIC_CLASSES ~ paste0(gs_name, " (retrotransposon)"),
      gs_name %in% TE_NUCLEAR_CLASSES     ~ paste0(gs_name, " (DNA transposon)"),
      TRUE                                ~ gs_name
    )
  ) %>%
  as.data.frame()

T2G_class <- as.data.frame(T2G_class)

export_te_genesets_gmt(
  list(T2G = T2G_class, T2N = T2N_class),
  file.path(outdir, paste0(project_id, "_TE_class.gmt"))
)

message("[done] Outputs written under: ", normalizePath(outdir))
```

## Output Files

| File | Description |
|------|-------------|
| `<id>_combined_DGEList.rds` | Combined gene+TE edgeR DGEList; `$genes` carries `feature_type`, `is_te`, `subfamily`, `family`, `class`, `replication_type`; TMM-normalized |
| `<id>_TE_family.gmt` | Family-level TE geneset GMT (TERM2GENE `gs_name`/`gene_symbol`); input to `te-geneset-gsea` |
| `<id>_TE_class.gmt` | Class-level TE geneset GMT (recipe-built); input to `te-geneset-gsea` |

> The combined matrix is valid only because exonic TE loci were subtracted upstream
> (`bedtools subtract`) in `star-te-preprocessing`, so no read is double-counted. Exon
> subtraction stops double-counting (necessary) but does **not** equalize the gene/TE
> measurement bases — mutual exclusivity is necessary, not sufficient.

> **Joint normalization/DE caveats (graded options, not mandates — grades + gaps in
> `te-gene-featurecounts/SKILL.md` "Evidence & open questions"; the joint matrix itself is grade
> A).** When this combined DGEList goes into joint normalization/DE:
> - **Size factors from genes only — grade B / contested:**
>   `estimateSizeFactors(dds, controlGenes = which(type == "gene"))`. TE-Seq advocates it (the
>   `-M`-inflated, long-tailed TE minority can drag gene LFCs); TEtranscripts **pools** instead.
>   Sanity-check against pooled factors.
> - **Valid for within-feature-type, across-sample DE only — grade C / inference** (gene-vs-sample,
>   TE-vs-sample).
> - **Never compare gene-vs-TE magnitude within a sample — grade C / inference**, and treat "TE %"
>   as a QC band, not biology — genes and TEs sit on different strandedness / multimapper / length
>   bases.
> - **No TPM/FPKM for TE rows — grade C / inference** — a summed multi-locus subfamily has no single
>   length; use model-normalized counts / logCPM / DESeq2 LFCs only.
>
> If TE rows were counted stranded with a sense/antisense split upstream (`--te-strand
> sense_antisense`), keep sense and antisense as separate TE features — the more principled
> best-practice (**grade B / SQuIRE-specific**) for preserving bidirectional TE biology without
> breaking gene-comparability. The field is split (TEtranscripts defaults `--stranded no`), so
> `-s 0` standalone matrices remain valid and mode-switching is not required.

## Key column contracts

| Column | Source | Notes |
|--------|--------|-------|
| `feature_type` | `create_combined_dge()` → `$genes` | `"gene"` or `"te"` |
| `is_te` | `build_te_annotation()` / `$genes` | logical |
| `subfamily` | `build_te_annotation()` | gene symbol slot for GSEA (`gene_symbol` column in GMTs) |
| `family` | `build_te_annotation()` | family-level grouping variable |
| `class` | `build_te_annotation()` | class-level grouping variable |
| `replication_type` | `build_te_annotation()` | `"cytoplasmic"` / `"nuclear"` / `NA` |

> **GSEA ID space:** TE GMT `gene_symbol` = subfamily. Rank by **subfamily** when preparing
> a ranked list for GSEA; do not use Ensembl IDs. See `te-geneset-gsea` skill for details.

## Relaxed `min_size` for class-level GSEA

Only ~6 TE classes exist in a typical mouse matrix. Applying the default `min_size = 5`
can drop most sets — use `min_size = 2` or `1` for class-level GSEA. See `te-geneset-gsea`
for the recommended filter strategy.

## Note on T1b — class-level `source()` hard-error

`R/create_te_genesets.R:109` (inside `level == "class"`) runs
`source("01_modules/TE-RNAseq-toolkit/R/te_utils.R")` unconditionally. Pre-sourcing does NOT
neutralize this: R's `source()` opens files by PATH regardless of in-scope symbols. When the
relative path does not resolve from the recipe's working directory (e.g., the TE toolkit is not
wired as a submodule), `create_te_genesets(te_ann, level = "class")` **hard-errors**. The
recipe above sidesteps this by building the class T2G/T2N directly from the already-sourced
`TE_CYTOPLASMIC_CLASSES`/`TE_NUCLEAR_CLASSES` constants. This is the correct workaround until
`R/create_te_genesets.R` is made self-locating (follow-up S12, out-of-scope).

## Customization Points

1. **File paths**: Update `counts_te_fp`.
2. **Output directory**: Change `outdir` as needed.
3. **Metadata / samples**: Ensure `samp_df` rownames match count column names.
4. **TE format**: TE IDs are expected in `Subfamily:Family:Class` format (e.g.
   `L1Md_A:L1:LINE`), as produced by `star-te-preprocessing` and parsed by
   TE-RNAseq-toolkit v2.0.3 `R/te_utils.R::parse_te_id`.
5. **GMT handoff**: Pass `<id>_TE_family.gmt` and `<id>_TE_class.gmt` to
   `te-geneset-gsea` for downstream pathway analysis.
