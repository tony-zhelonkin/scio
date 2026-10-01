# Interpretation protocol

## Before the run

Write down the expected top-hit categories. A signature with no expected category is too vague
for CoReSh; sharpen it first.

| Query | Expected top-hit categories |
|---|---|
| `HALLMARK_HYPOXIA` | HIF-1a activation, hypoxia chambers, tumour hypoxia, VHL loss |
| `HALLMARK_INTERFERON_GAMMA_RESPONSE` | IFN-gamma stimulation, viral infection, M1 polarisation |
| Iron uptake (`TFRC`, `STEAP3`, `SLC11A2`) | Erythroid differentiation, macrophage iron recycling, liver iron overload, chelation |
| DC immunogenic markers | LPS or poly(I:C), TLR agonists, DC maturation time courses |
| DC tolerogenic markers | IL-10 or TGF-b treatment, tumour-associated DCs, Treg-inducing contexts |
| Cross-presentation | Cross-priming, TAP studies, Batf3 DCs |
| Open question | Run related positive controls beside it and read convergence |

Zero expected categories in the top 20 means a broken query: check species, `size`, and the
`gene_to_entrez()` warning.

## Read the top 20

1. **Fetch metadata.** Titles are not in the snapshot.

   ```r
   meta <- GEOquery::getGEO(gse_id, GSEMatrix = FALSE)          # full record
   url  <- sprintf("https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=%s&targ=self&form=text&view=brief", gse_id)
   head(readLines(url), 20)                                      # summary only
   ```

   The web UI shows titles for the same accessions. Keep the lookup; `coresh_labels(titles = )`
   consumes it.

2. **Categorise each hit.**

   | Category | Meaning |
   |---|---|
   | Expected | Confirms the signal |
   | Adjacent | Plausibly related; follow up |
   | Novel | Hypothesis lead; verify before use |
   | Cell line / CCLE | Proliferation-confounded; low weight |
   | Noise | `size < 3` or incoherent metadata; discard |

3. **Score the query.**

   | Expected + adjacent in top 10 | Action |
   |---|---|
   | ≥5 | Robust; proceed to derived sets |
   | 2-4 | Noisy; refine the query first |
   | ≤1 | No signal; rebuild the signature |

## Convergence

A dataset in the top hits of several related queries is a high-confidence lead. Examine it
before any single-query hit.

```r
conv <- coresh_convergence(hits, top_n = 10L, min_queries = 2L)
# gse, gpl, n_queries, queries, best_rank, mean_pct_var
```

## Controls

| Control | Genes | Expected |
|---|---|---|
| Positive | `HALLMARK_HYPOXIA` | Hypoxia and HIF series in the top 20 |
| Housekeeping | `ACTB`, `GAPDH`, `B2M`, `HPRT1`, `TBP`, `PPIA` | No coherent biology in top hits |
| Random | 50 genes drawn with a fixed seed | No coherent biology in top hits |
| Sex-linked | `XIST`, `RPS4Y1` | Sex-variable series; confirms the machinery |

A real query whose top hits resemble the housekeeping control is housekeeping-driven. Filter
and rerun (`references/query-design.md`).

## Red flags

| Flag | Meaning |
|---|---|
| `size < 3` on most top hits | Species mismatch or platform coverage |
| Top hits from one lab, year or platform | Batch-driven; deprioritise |
| Top hits all tumour cell lines | Proliferation signal |
| Top hits span unrelated biology | Query too broad or noisy |
| `p_value` order disagrees with `pct_var` order | Trust `p_value`; high-`totalVar` datasets inflate `pct_var` |
| One GSE above 50% `pct_var` for many queries | Outlier dataset; inspect manually |
| Many rows in `attr(hits, "skipped")` | Snapshot defect; report it |

## Write-up

Record for every reported CoReSh finding:

- Exact query Entrez IDs and species (`hsa` or `mmu`)
- Snapshot: `attr(hits, "provenance")$snapshot`
- Ranking (`pct_var` or `p_value`), `sample_size`, `seed`, and the hit cutoff
- Top hits as `(gse, gpl)` with category, `p_value` and `log2err`
- For derived sets: `gsdb_info(db)$provenance` and `attr(db, "set_provenance")`
- bulkiRNA version: `packageVersion("bulkiRNA")`

Report `p_value` as a ranking statistic. The compendium p-values are not independent, so no
adjusted p-value is valid.
