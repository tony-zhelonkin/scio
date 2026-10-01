# What `pct_var` measures

## The score

For a query of `k` genes present in a dataset with centred matrix `E` (genes x columns):

```
p        = colSums(E[query, ])          # summed query profile
score    = sum(p^2)
pct_var  = score / k / totalVar * 100
```

This is `fgsea`'s GESECA score for one gene set. `coresh_match()` computes it against the
stored `totalVar`; `coresh_search()` applies it to every dataset.

`score / k` is a closed-form lower bound on the variance the query genes carry along their own
mean direction: the quantity PCA would find from a leading eigenvector, without the
eigendecomposition. It equals mean per-gene variance plus mean cross-gene covariance.

| Query genes | `score / k` ÷ mean gene variance |
|---|---|
| Independent | ~1 |
| Perfectly coregulated | `k` |

Dividing by `k` removes query-size dependence. Dividing by `totalVar` removes depth and scale.
The result is comparable across the compendium with no contrast and no design.

## Chunk objects

Each `*_full_objects.qs2` chunk holds ~500 dataset objects.

| Field | Meaning |
|---|---|
| `gseId`, `gplId` | GEO series and platform; the pair identifies a dataset |
| `E1024` | `round(E * 1024)`; `E` is centred, at most 20 columns in measured chunks |
| `rownames` | Integer Entrez IDs, one per row; IDs can repeat |
| `totalVar` | Total variance of `E`, computed before quantization |
| `samples`, `nsamples`, `wordMatrix` | Sample ids, sample count, text features |

About a fifth of datasets are PCA-reduced: their columns are principal components. The score
and `totalVar` are both invariant to an orthogonal rotation of the columns, so the reduction
loses only the variance in dropped components. Chunk matrices are already centred; pass
`center = FALSE` when running `gs_coregulation()` on one.

Dataset titles are not in the snapshot. Fetch them from GEO when reading hits.

## GESECA p-values

`coresh_search(pvalues = TRUE)` calls `fgsea::geseca()` per dataset with `sample_size = 21L`,
`seed = 1L` and `eps = 1e-300`, the upstream vignette values.

| Ranking | Upstream cost, full compendium | Use |
|---|---|---|
| `pct_var` descending | 10-20 s | Screening, iteration |
| `p_value` ascending | a couple of minutes | Reporting; upstream calls it more specific |

- `sample_size` sets estimator precision: larger values shrink `log2err`.
- The same seed reproduces the same p-value. A different seed, `sample_size` or implementation
  moves it; compare such p-values within `log2err`.
- `log2err = Inf` marks a set past reliable resolution. Report it.
- The p-value is for ranking. There is no `padj`.
