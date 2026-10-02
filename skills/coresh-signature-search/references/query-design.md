# Query design

## Size regime

| Unique genes | Behaviour |
|---|---|
| 3-5 | Noisy; one highly variable gene dominates. Run several related queries and read convergence |
| 10-200 | Target range |
| 200-1000 | Diluted; `pct_var` drifts toward "how variable is this dataset" |
| >1000 | A proxy for total variance; use GSEA on leading edges instead |

`coresh_search()` requires at least three unique Entrez IDs per query and removes duplicates
with a message.

## Signature sources

| Source | Take | Notes |
|---|---|---|
| DE table | top 20-100 by moderated t, one direction | Up only by default; both sides when the biology is bidirectional |
| Cluster markers | top 20-50 per cluster | Markers carry their cluster's biology |
| GSEA leading edge | the edge genes of one set | Strong, already-coherent queries |
| Curated set | MSigDB Hallmark via `gsdb_msigdb()` | `HALLMARK_HYPOXIA` is the positive control |

Rank on the moderated t: it is continuous and calibrated at the top of the list.

```r
syms    <- filter_confounder_genes(head(de$Symbol[order(-de$t)], 50))
queries <- list(contrast_up = gene_to_entrez(syms, species = "human"))
```

`gene_to_entrez()` warns on every unmapped symbol and retries retired symbols against the alias
table. Read the warning: lost genes shrink the query.

## Confounder filtering

Filter before building the query, unless the category is the biology under study.

| `filter_confounder_genes(drop = )` | Why |
|---|---|
| `"ribosomal"` | Drives variance in every proliferating sample |
| `"mito"` | Tracks QC and dissociation state |
| `"hemoglobin"` | Dominates blood-contaminated samples |
| `"cell_cycle"` | Drives variance in every cycling-cell study |
| `"sex"` | Sex effect in sex-confounded comparisons |

Pseudogenes (`^[A-Z0-9]+P\d+$`) are outside the function; drop them by pattern when present.

## Cross-species queries

Query each species' compendium with that species' Entrez IDs. For a human signature on `mmu/`,
map symbols to mouse orthologs first (`babelgene::orthologs()` or `homologene`), then call
`gene_to_entrez(species = "mouse")`. Concordant top hits across `hsa/` and `mmu/` are strong
evidence.

## Query sets

- Run related queries together and read `coresh_convergence()`.
- Run matched pairs (healthy vs tumour, high vs low marker, cluster vs neighbour) and examine
  datasets that rank high for both members.
- Include `HALLMARK_HYPOXIA` and a housekeeping set in every batch as controls.

## DC_hum_verse query set

`coresh-slice` in DC_hum_verse holds the reference query set (Q1-Q16).

| Query type | Typical size | Notes |
|---|---|---|
| Iron program (uptake, storage, export, regulatory) | 3-12 | Run at least four together; trust convergence over any single ranking |
| DC state program (immunogenic, tolerogenic, antigen presentation, cross-presentation) | 10-40 | Drop HLA genes for the mouse compendium |
| Cluster markers | top 20 by t | Filter ribosomal and mito |
| TFRC-high vs TFRC-low | top 20-50 by t, pseudobulk DE | Expect iron-uptake and haem-biosynthesis series near the top |
