# Training, GPU, and reproducibility

A fit is finished when three things are on disk: the weights from its best validation epoch, the
curve that shows how it got there, and the record that lets the next run reuse or reproduce it.
Every call below was run on scvi-tools 1.2.0, Lightning 2.6.5 and torch 2.13 on CUDA. Arguments
move between releases, so check `help(model.train)` on the installed version before copying one.

## Global settings

```python
import scvi
import torch

scvi.settings.seed = 42                          # seeds torch, numpy and the train/validation split
torch.set_float32_matmul_precision("high")       # tensor-core matmul on Ampere and newer GPUs
scvi.settings.dl_num_workers = 0                 # the installed default; raise it after a benchmark
```

## A train call that keeps its best state

```python
import contextlib
import functools


@contextlib.contextmanager
def trusted_torch_load():
    """Unpickle checkpoints this run wrote itself; torch.load returns to its default on exit."""
    original = torch.load
    torch.load = functools.partial(original, weights_only=False)
    try:
        yield
    finally:
        torch.load = original


best = scvi.train.SaveCheckpoint(
    dirpath=f"{run_dir}/checkpoints", monitor="elbo_validation", load_best_on_end=True,
)
with trusted_torch_load():
    model.train(
        max_epochs=400,
        train_size=0.9,
        batch_size=128,
        early_stopping=True,
        early_stopping_monitor="elbo_validation",
        early_stopping_patience=45,
        check_val_every_n_epoch=1,
        callbacks=[best],
    )
```

Each piece has one job:

- **Early stopping** ends the fit after `early_stopping_patience` validation checks without
  improvement, and leaves the model at the weights of its last epoch.
- **`SaveCheckpoint(load_best_on_end=True)`** writes the best validation state to `dirpath` and
  loads it into the model when training ends. This is the step that makes the latent you export the
  best-validation latent. The checkpoint directory also lets a later session resume or audit the fit.
- **`trusted_torch_load`** is needed because torch 2.6 and later load with `weights_only=True`, and
  scvi-tools 1.2.0 checkpoints and saved models carry numpy and `collections` objects that this mode
  refuses. Without it, the restore raises `UnpicklingError` at the end of training, and
  `SCVI.load` raises it on a model the same process saved. Keep the scope to files your own runs wrote.
- **`early_stopping_min_delta`** defaults to 0. Any strict decrease in validation ELBO then counts
  as an improvement and resets patience, so a long, slowly falling tail can carry a fit to
  `max_epochs`. A positive value is a decision about how large a gain is worth waiting for, in the
  units of the monitored metric, and it belongs to the dataset.
- **Patience counts validation checks.** With `check_val_every_n_epoch=k` it spans `k × patience`
  epochs.

`model.history` and checkpoint names (`epoch=50-step=255-elbo_validation=…`) count epochs from zero.

## How many updates a fit receives

An epoch is one pass over the training cells, so it holds `ceil(n_train / batch_size)` optimizer
steps. The epoch count alone says little about how much a model has trained: 2,000 training cells at
`batch_size=1024` give two steps per epoch, and 400 epochs give 800 updates. The installed default
`max_epochs` reflects this, giving `min(400, 400 × 20,000 / n_cells)` epochs, which is the full 400
for any dataset up to 20,000 cells. For a small dataset or a small subset (one lineage, one lens),
the levers are a smaller batch, more epochs, or both. Choose them by comparing fits, as below.

The KL warmup (`plan_kwargs={"n_epochs_kl_warmup": …}`, default 400 epochs) ramps the KL weight in
the training loss from 0 to 1. The logged `elbo_*` metrics always carry the full KL term, so the
ELBO can rise during warmup while the model is training well.

## Reading a finished fit

A fit ends in one of two recorded states: stopped early
(`model.trainer.early_stopping_callback.stopped_epoch > 0`) or capped at `max_epochs`. The
trainer lives only on the model that trained, so the stop state goes into the run record before
the model is saved. Early stopping
and the cap can meet: a fit with early stopping enabled still reaches the cap when validation ELBO
keeps improving by small amounts until the last epoch. A capped fit raises a question that the saved
curve answers:

1. Plot `elbo_train` and `elbo_validation` per epoch. Both are minibatch estimates, so they move up
   and down between epochs. Read the trend.
2. Find the best validation epoch and how far it sits from the end.
3. Compare the mean validation ELBO over the final window of epochs with the window before it, as a
   relative change. A change of the order of the epoch-to-epoch noise is a plateau. A tail that is
   still falling steadily is the case for a longer fit.
4. Fit the longer or smaller-batch variant, and compare the two latents.

The curve describes the optimizer. The scientific test is the latent: the share of each cell's k
nearest neighbours that both fits have in common, the agreement of clusters or labels, batch mixing,
and the separation of known marker populations. A longer fit earns its place when it changes the
latent in a way the biology needs.

A widening gap with validation ELBO turning upward while training ELBO keeps falling marks
overfitting. Raise `weight_decay` in `plan_kwargs`, or lower `n_latent` or `n_hidden`.

## Warnings that concern throughput and logging

Two Lightning warnings appear often in scvi-tools runs. Both concern speed and logging, and the
validation curve stays the measure of convergence:

| Warning | What it measures | Response |
|---|---|---|
| `The 'train_dataloader' does not have many workers … num_workers=N` | N is derived from the machine's CPU count | Benchmark the worker count as in the next section |
| `The number of training batches (n) is smaller than the logging interval Trainer(log_every_n_steps=10)` | step-level logging cadence | Epoch-level `history` stays complete. Pass `log_every_n_steps=1` when step-level curves are wanted |

## Data-loader workers

`scvi.settings.dl_num_workers` sets how many processes assemble minibatches, and
`scvi.settings.dl_persistent_workers` keeps those processes alive between epochs. Both default to
the values that load in the main process (`0` and `False`), and every training, validation and
inference loader reads them. The right count depends on where loading time goes: an in-memory
sparse AnnData hands the GPU a batch quickly from the main process, while backed or very large data
can keep the GPU waiting.

Choose the count by measurement on the machine and data at hand:

```python
for workers in (0, 2, 4, 8):
    scvi.settings.dl_num_workers = workers
    scvi.settings.dl_persistent_workers = workers > 0
    # set up and train a fresh model for 3–5 epochs; record seconds per epoch
```

Keep the fastest count, and keep `0` when the counts tie. Each worker is a process with its own
share of host memory, and workers hand batches to the trainer through `/dev/shm`. A container's
`/dev/shm` defaults to 64 MB, so check `df -h /dev/shm` before raising the count there; a full
`/dev/shm` ends a worker with a bus error. On one RTX 5000 Ada with 20,000 in-memory cells at
`batch_size=128`, `0` workers gave the shortest epoch, and persistent workers recovered most of the
time that respawning workers costs each epoch.

## Overrides by situation

| Situation | Change |
|---|---|
| Small dataset or subset, few steps per epoch | Compare a smaller `batch_size` and a longer `max_epochs` against the current fit, on the latent |
| Very large or backed dataset (>1M cells) | `batch_size=512–1024`; benchmark `dl_num_workers` (Data-loader workers) |
| GPU OOM | Lower `batch_size`, reduce `n_hidden` |
| Host memory runs out, or a worker dies with a bus error | `dl_num_workers=0`, or a larger `/dev/shm` |
| Validation ELBO spikes or turns NaN | Lower `lr` to `5e-4` in `plan_kwargs`, raise `weight_decay` |
| scArches query fine-tuning | `max_epochs=200`, `plan_kwargs={"weight_decay": 0.0}` |

## Save, load and record

```python
model.save(f"{run_dir}/model", save_anndata=False, overwrite=True)
with trusted_torch_load():
    model = scvi.model.SCVI.load(f"{run_dir}/model", adata=adata)
```

`model.save` keeps the weights, `history`, `train_indices` and `validation_indices`; the checkpoints
written by `SaveCheckpoint` carry weights alone. `save_anndata=False` keeps a sharable model small,
with the AnnData kept beside it.

Write one record per fit beside the latent:

- epochs run, best epoch and best validation ELBO, whether it stopped early or reached the cap, and
  the late-window relative change;
- whether the exported weights are the best-validation or the final-epoch state;
- the checkpoint path and the split indices;
- the seed, the installed versions of scvi-tools, Lightning and torch, and the GPU;
- a fingerprint of the fit's actual inputs: the cells, the genes, the counts they were taken from
  and the training recipe.

The fingerprint decides when a latent can be reused. A fit depends on its own cells, genes, counts
and recipe. Hash exactly those, per model, and a change elsewhere (a label, an annotation column, a
sibling subset's roster) reuses the latent, while a change to the inputs retrains it.
