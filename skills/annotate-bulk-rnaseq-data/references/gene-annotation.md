# Gene-Symbol Annotation (the usual case)

Annotate a bulk RNA-seq gene count matrix and assemble an edgeR `DGEList` with the installed
`bulkiRNA` package. Every preprocessed dataset needs this step.

> **Shared principle (also in SKILL.md):** annotate before filtering. Ensembl IDs dropped by a
> filter cannot be recovered.

## Inputs

- A gene count matrix: featureCounts (post-processed or raw) or Salmon gene-level, Ensembl IDs
  in the first column.
- A sample sheet whose sample-ID column matches the count columns.
- `02_analysis/config/analysis_config.yaml`: `project.id`, `project.genome_build`, and
  `reference.ensembl_version` when the project pins an Ensembl release.

## Exports

| Step | Export | Contract |
|---|---|---|
| Read counts | `read_counts_matrix(path)` | Detects featureCounts, Salmon and generic shapes; strips aligner suffixes from sample names; Salmon `gene_name` lands in `attr(, "input_gene_name")`, keyed by version-stripped ID |
| Read samples | `read_metadata(path, sample_col_candidates =)` | `.xlsx` or delimited; renames the sample column to `Sample_ID` |
| Annotate | `annotate_genes(ens_ids, species =, use_biomart =, input_gene_name =, biomart_version =)` | One row per input ID: `Symbol, Ensembl, ENTREZID, gene_biotype, input_gene_name`. biomaRt adds `gene_biotype` when the network is up and leaves the org.db result intact when it is down |
| Build | `build_dge(count_mat, samples_df, genes_df)` | Asserts sample and gene order, rounds non-integer counts with a message, applies TMM |
| Record | `write_session_provenance(path, genome_build =, ensembl_version =)` | Genome build, requested and resolved Ensembl release, package versions, RNG, `sessionInfo()` |

## How-to

```r
suppressPackageStartupMessages({ library(bulkiRNA); library(yaml) })
cfg <- read_yaml("02_analysis/config/analysis_config.yaml")
out <- file.path("03_results/objects", "00_annotate"); ensure_dir(out)

counts  <- read_counts_matrix(cfg$inputs$counts)
samples <- as.data.frame(read_metadata(cfg$inputs$samples,
                                       sample_col_candidates = cfg$annotation$sample_col))
rownames(samples) <- samples$Sample_ID
stopifnot(setequal(colnames(counts), rownames(samples)))
counts <- counts[, rownames(samples)]

genes <- as.data.frame(annotate_genes(
  rownames(counts), species = cfg$annotation$species,
  use_biomart = cfg$annotation$use_biomart,
  input_gene_name = attr(counts, "input_gene_name"),
  biomart_version = cfg$reference$ensembl_version))
rownames(genes) <- rownames(counts)

dge <- build_dge(counts, samples, genes)
saveRDS(dge, file.path(out, paste0(cfg$project$id, "_DGEList.rds")))
write_session_provenance(file.path(out, "provenance.txt"),
                         genome_build = cfg$project$genome_build,
                         ensembl_version = cfg$reference$ensembl_version)
```

Filtering and re-normalisation follow in the next stage; skill `bulkirna` holds that recipe.

## Points to set per project

1. **Species.** `"Mus musculus"` or `"Homo sapiens"`; aliases such as `"mouse"` work.
2. **Ensembl release.** `biomart_version = NULL` floats; the provenance file then records the
   release biomaRt resolved.
3. **Two count sources over one annotation.** Salmon's `gene_name` uses the same GENCODE IDs as a
   featureCounts run on that GTF. Pass the Salmon `input_gene_name` attribute when annotating the
   featureCounts matrix too.
4. **Unresolved symbols (1.1.0).** `Symbol` falls back to the Ensembl ID where org.db and biomaRt
   have no name. Fill it from `input_gene_name` when the project wants GENCODE names:
   `i <- genes$Symbol == genes$Ensembl & !is.na(genes$input_gene_name)`.

## Outputs

| File | Content |
|---|---|
| `<id>_DGEList.rds` | Raw counts, `$genes` annotation, `$samples` metadata, TMM factors |
| `provenance.txt` | Build, Ensembl release, versions, `sessionInfo()` |

## Combining with TEs

For a single gene + TE `DGEList`, read `references/te-annotation.md`. The `genes` frame produced
here feeds `create_combined_dge()` there.
