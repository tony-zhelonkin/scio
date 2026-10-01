# CoReSh-to-GSEA bridge

Each top-ranking dataset defines a coregulation module: the query genes plus every gene that
moves with them in that dataset's context. The bridge turns those modules into a `gs_db` and
tests it on your own contrast.

## Mechanism

`coresh_loadings()` projects every gene in one dataset onto the unit-normalised query profile
and keeps the `top_n` genes by absolute loading. `coresh_sets()` runs it for every hit, maps
Entrez to symbols with `entrez_to_gene()`, drops sets outside `[min_size, max_size]`, orders sets
by CoReSh rank, and removes a lower-ranked set whose Jaccard overlap exceeds
`jaccard_threshold`. Set ids are `CORESH_<query_name>_<GSE>`.

## Workflow

| Step | Call | Check |
|---|---|---|
| 1. Search | `hits <- coresh_search(queries, species = "human", pvalues = TRUE)` | `attr(hits, "skipped")` row count |
| 2. Read | top 20 per query, `references/interpretation-protocol.md` | ≥5/10 interpretable |
| 3. Converge | `coresh_convergence(hits, top_n = 10L, min_queries = 2L)` | shared hits examined first |
| 4. Select | `top <- hits[hits$rank <= 5L, ]`, or a curated subset | keep `gpl` in the table |
| 5. Build | `db <- coresh_sets(top, queries, species = "human")` | skip counts in the message; `length(db)` |
| 6. Test | `gs_test(ranks, db, contrast = ..., min_size = 15, max_size = 500)` | `ranks` from `gs_ranks()` on the moderated t |
| 7. Plot | `gs_plot_dot(res)`, `gs_save()` | labels show accession and platform |
| 8. Trace | `attr(db, "set_provenance")` | each enriched set maps to its GSE |

`gsdb_coresh(queries, species, top_hits = 5L)` runs steps 1, 4 and 5 in one call with a `pct_var`
ranking. Use the explicit steps when hits are chosen by `p_value`, by convergence, or by hand.

```r
db  <- coresh_sets(top, queries, species = "human", top_n = 50L,
                   min_size = 15L, max_size = 500L, jaccard_threshold = 0.8,
                   verbose = TRUE)
res <- gs_test(ranks, db, contrast = cfg$contrasts$name, min_size = 15, max_size = 500)
gs_write(res, "03_results/<stage>/tables", name = "coresh_derived")
```

## Rules

- **Treat derived sets as unsigned.** The overall sign of the query direction is arbitrary.
  Read both tails of the GSEA result. Merge no signed leading edges across hits.
- **Keep the query definitions.** Provenance stores query names and unique ID counts. The IDs
  live in project config.
- **Keep species aligned.** `species` in `coresh_sets()` selects both the chunk tree and the
  Entrez → symbol mapping. Your ranks must use the same species' symbols, or orthologs.
- **Label from provenance.** `db` carries `coresh_labels()` labels by default. For GEO titles,
  build `coresh_labels(attr(db, "set_provenance"), titles = title_lookup)` and pass it to
  `gs_plot_running(labels = )`. `gsdb_register(pathway_names = )` also accepts it but returns a
  database without CoReSh provenance; write the provenance out first.

## Provenance to keep

`attr(db, "set_provenance")` holds `set_name`, `query_name`, `gse`, `gpl`, `chunk_path`,
`loading_cutoff`, `rank_in_coresh`. `gsdb_info(db)$provenance` holds the snapshot, species and
set-building parameters. Write both beside the GSEA tables.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| Sets look alike across queries | Housekeeping-heavy query | Filter the query (`references/query-design.md`) |
| A set is mostly the query | Query dominates its own loadings | Drop it as trivial |
| No set enriches in your data | Low DE power, mismatched context, or broad query | Check the GSE metadata before trusting its set |
| Empty database with a message | Every hit was size-filtered or deduplicated | Raise `top_n` or relax size bounds; report it |
| `coresh_sets()` stops | Every extraction failed | Check `chunk_dir`, species and the hit table's snapshot |
