# Troubleshooting playbook (append-only)

This file grows as agents encounter novel failure modes across the scvi-tools cluster. The format is deliberately minimal: **symptom → cause → fix**, optionally with a code snippet.

> Append new entries at the bottom. Do not delete or reorder — this is a log, not a reference tree.

---

## Template

```
### <one-line symptom>

**Cause:** <what actually went wrong>
**Fix:** <concrete steps>
**Applies to:** <scVI | scANVI | MultiVI | all | ...>
**Seen:** <YYYY-MM-DD, skill that referred you here>
```

---

## Entries

### Training stalls with no GPU utilization

**Cause:** PyTorch CPU wheel installed despite a CUDA-capable GPU.
**Fix:**
```bash
pip uninstall torch scvi-tools
pip install -U "scvi-tools[cuda]"
python -c "import torch; assert torch.cuda.is_available()"
```
**Applies to:** all
**Seen:** 2026-04-20, initial seed

### KeyError on gene names when loading query data

**Cause:** Query `var_names` are Ensembl IDs while reference was trained on gene symbols (or vice versa).
**Fix:** Harmonize before `prepare_query_anndata`:
```python
query_adata.var_names = query_adata.var["gene_symbol"].astype(str)
query_adata.var_names_make_unique()
```
**Applies to:** scArches on any model
**Seen:** 2026-04-20, initial seed

### Latent space collapses to a single cluster

**Cause:** Too few optimizer updates (a short fit, or a small subset at a large batch size), or `n_latent` set too low.
**Fix:** Plot `model.history["elbo_validation"]` and find the best epoch; compute the steps per epoch; raise `n_latent` to 20–30; compare a smaller-batch or longer fit on the latent (`training-and-gpu.md`, "Reading a finished fit").
**Applies to:** scVI, scANVI, MultiVI
**Seen:** 2026-04-20, initial seed
