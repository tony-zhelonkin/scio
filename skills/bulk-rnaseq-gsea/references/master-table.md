# Master table

`master_gsea_table.csv` holds every gene-set row of the project, one per pathway, database and
contrast. It is the bridge to `bulk-rnaseq-pathway-explorer` and to cross-stage summaries.
Contracts: `?gs_to_master`, `?gs_validate_master`, `?gs_master_columns`.

## Rules

1. **Build it in its own stage, from scratch, on every run.** Read each compute stage's tables
   with `gs_read()` and write the whole file. A re-run then replaces rows by construction.
2. **Pass membership and universe.** `gs_to_master(db = )` takes the `gs_db` object and
   `universe` the ranked gene names; together they fill `genes_full_set`. With `db = NULL` that
   column is `NA`.
3. **Validate before writing.** `gs_validate_master()` stops on every schema or invariant problem
   at once.
4. **Columns come from the schema.** `gs_master_columns()` lists them in order; `nes` is lower
   case and `direction` is `Up`, `Down` or `NS`.

## Assembly

```r
inp <- readRDS(file.path(gsea_dir, "gsea_inputs.rds"))       # list(dbs, ranks)
res <- gs_read(file.path(gsea_dir, "tables"), name = "gsea")

master <- do.call(rbind, lapply(gs_split(res, by = c("database", "contrast")), function(x)
  gs_to_master(x, db = inp$dbs[[x$database[1]]],
               universe = names(inp$ranks[[x$contrast[1]]]))))

stopifnot(!anyDuplicated(master[c("pathway_id", "database", "contrast")]))
gs_validate_master(master)
readr::write_csv(master, "03_results/tables/master_gsea_table.csv")
```

Add each further GSEA stage (custom databases, CoReSh-derived sets) to the same loop over its own
`gsea_inputs.rds` and tables.

## Derived tables

Written beside the master by the same stage:

| File | Content |
|---|---|
| `master_gsea_significant.csv` | rows with `padj < 0.05` |
| `gsea_summary_stats.csv` | per `database`, `contrast`, `direction`: total rows, significant rows, mean `abs(nes)` among significant |
| `master_de_table.csv` | per contrast and gene: `contrast`, `gene_symbol`, `ensembl_id`, `ensembl_id_base`, `logFC`, `AveExpr`, `t`, `P.Value`, `adj.P.Val`, `B` |

`gs_write()` already writes a per-stage `_overview/gsea_summary.tsv`.

## Rows from other methods

| Source | Route |
|---|---|
| ORA, GSVA or score-matrix limma | `gs_to_master()` refuses a non-NES `stat`; `stat_as_nes = TRUE` writes it to `nes` and the `database` key names the method |
| GATOM module | register its genes as a set and test it with GSEA (`custom-databases.md`); its row is then ordinary |
| TF activity, PROGENy | skill `bulk-rnaseq-activity-inference`; validate their master rows with `gs_validate_master()` |

A GATOM row built from mean edge logFC is a pseudo-NES. Keep it out of the NES columns of
figures that compare against GSEA rows.
