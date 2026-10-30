# Pre-train checklist (walk before calling `.train()`)

Run through these eight checks before training any scvi-tools model. Each item has a one-line verification you can paste directly.

1. **Raw counts present.** `adata.X` (or the named layer) holds integer counts, not normalized values.
   ```python
   import numpy as np
   X = adata.layers["counts"] if "counts" in adata.layers else adata.X
   assert np.all(X.data == X.data.astype(int)), "Non-integer values — not raw counts"
   ```

2. **Batch key is a categorical string.**
   ```python
   assert adata.obs["batch"].dtype.name in ("category", "object"), "Cast batch_key to str"
   ```

3. **`setup_anndata` has been called on the current adata.** Re-run if you subset, concat, or changed a registered column.
   ```python
   assert "_scvi_manager_uuid" in adata.uns, "Run Model.setup_anndata(adata, ...)"
   ```

4. **HVG / feature selection done.** scRNA models expect ~2–5k HVGs selected with `flavor="seurat_v3"` on raw counts.

5. **Sparse matrix in CSR format.**
   ```python
   import scipy.sparse as sp
   if sp.issparse(adata.X):
       assert sp.isspmatrix_csr(adata.X), "Convert to csr_matrix"
   ```

6. **GPU is actually being used (if expected).**
   ```python
   import torch
   print("CUDA:", torch.cuda.is_available())
   ```

7. **scArches-compatible flags set if this reference will be reused.** Required: `use_layer_norm="both"`, `use_batch_norm="none"`, `encode_covariates=True`. Not retrofittable.

8. **The fit keeps its best state and its record.** `callbacks` carries `SaveCheckpoint(monitor="elbo_validation", load_best_on_end=True)` inside `trusted_torch_load()`, and the run writes the validation curve, split indices and an input fingerprint (`references/training-and-gpu.md`).
   ```python
   print("steps per epoch:", -(-int(0.9 * adata.n_obs) // batch_size))
   ```

## Extending this checklist

When you discover a preventable failure that should have been caught before `.train()`, add a numbered item here. Keep each item to one line + one verification block. Move anything bigger to `references/gotchas.md` or `references/troubleshooting.md`.
