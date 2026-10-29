# Critical gotchas (all scvi-tools models)

| Symptom | Cause | Fix |
|---|---|---|
| "RuntimeError: Expected integer tensor" | Model got normalized / log-transformed values | Restore raw counts to `.X` or `.layers["counts"]`; re-run `setup_anndata` |
| Query mapping fails with KeyError on genes | Query `var_names` differ from reference | Subset query to reference genes; pad missing with zeros via `scvi.model.SCVI.prepare_query_anndata` |
| Batch correction has no effect | `batch_key` is numeric | Cast to str: `adata.obs["batch"] = adata.obs["batch"].astype(str)` |
| Model ignores biological sample variation | Using `batch_key` for donor in MrVI | MrVI distinguishes `sample_key` (biological) from `batch_key` (technical) |
| Training crashes after `adata = adata[mask].copy()` | Registration is stale | Re-run `setup_anndata` |
| Silent CPU-only training on a GPU box | PyTorch CPU wheel or driver mismatch | Install `scvi-tools[cuda]`; verify with `torch.cuda.is_available()` |
| OOM on a normally-sized dataset | CSC or dense `.X` | Convert to CSR: `adata.X = scipy.sparse.csr_matrix(adata.X)` |
| DataLoader hang / zombie workers | `dl_num_workers > 0` in some containers | `scvi.settings.dl_num_workers = 0` |
| scArches query won't load | Reference was trained without scArches flags | Reference needs `use_layer_norm="both"`, `use_batch_norm="none"`, `encode_covariates=True` |
| `_pickle.UnpicklingError: Weights only load failed ... GLOBAL numpy.core.multiarray._reconstruct` at the end of training or on `SCVI.load` | torch >= 2.6 loads with `weights_only=True`; scvi-tools 1.2.0 saved models and `SaveCheckpoint` checkpoints embed numpy and `collections` objects | Wrap the train call and the load in `trusted_torch_load()` from `training-and-gpu.md`, scoped to files your own runs wrote; third-party checkpoints keep the default |
| Latent collapses to ~1–2 effective dimensions | `n_latent` too small, or too few optimizer updates | Raise `n_latent` to 20–30; read the validation curve and the updates per epoch (`training-and-gpu.md`) |
| A capped fit is called undertrained | Early stopping with `min_delta=0` resets on every tiny gain, so a flat tail reaches `max_epochs` | Read the saved validation curve: best epoch, late-window relative change; compare a longer fit on the latent |
| Exported latent comes from the last epoch | Early stopping keeps final weights | `SaveCheckpoint(monitor="elbo_validation", load_best_on_end=True)` in `callbacks` |

## Extending this list

When you encounter a new failure pattern, add a row here and, if recurring across models, a short how-to in `troubleshooting.md`. Prefer extending this table over carving out a new skill.
