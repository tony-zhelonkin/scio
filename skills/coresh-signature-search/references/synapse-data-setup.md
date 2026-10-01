# Chunk tree: location, check, and a new snapshot

## Location

| Item | Value |
|---|---|
| Refcache source | `/data2/users/shared/refcache/coresh/` |
| Live snapshot | `current` → `syn66227307_20260721` |
| Layout | `current/preprocessed_chunks/{hsa,mmu}/*_full_objects.qs2` |
| Size | 89 `hsa` + 85 `mmu` chunk files, ~21 GB |
| Synapse project | `syn66227307`, <https://www.synapse.org/coresh> |

bulkiRNA resolves `chunk_dir = NULL` to `$REFCACHE_ROOT/coresh/current/preprocessed_chunks/<hsa|mmu>`
and records the snapshot that `current` points to. Pass `chunk_dir` to use a local copy.

```bash
docker run ... -v /data2/users/shared/refcache:/refcache:ro -e REFCACHE_ROOT=/refcache ...
```

## Check

```r
chk <- coresh_validate(species = "human")   # then species = "mouse"
chk[!chk$ok, ]
```

It prints every check: `qs2`, `coresh`, `BiocParallel`, `org.Hs.eg.db`, `org.Mm.eg.db`, the
resolved chunk directory, the chunk file count, and the structure of the first dataset. The
`coresh` row is informational: upstream ships no R functions.

## New snapshot (user runs this)

The download needs the user's personal Synapse token. Ask the user to run it.

1. Register at Synapse and accept the data-use terms.
2. Create a personal access token with `view` and `download`.
3. Install and configure the client:

   ```bash
   pip install --upgrade synapseclient
   synapse config            # paste the token; writes ~/.synapseConfig
   ```

4. Download into a dated snapshot directory beside `current`:

   ```bash
   cd /data2/users/shared/refcache/coresh
   mkdir syn66227307_YYYYMMDD && cd syn66227307_YYYYMMDD
   synapse get -r syn66227307      # resumable; rerun to continue
   ```

5. Run `coresh_validate(chunk_dir = "<new>/preprocessed_chunks/hsa")` and the `mmu` equivalent.
6. Repoint `current` once both pass. Results carry the new snapshot tag from then on.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| `REFCACHE_ROOT` is unset | Refcache not mounted | Mount it and set `REFCACHE_ROOT=/refcache`, or pass `chunk_dir` |
| `Unauthorized` on `synapse get` | Token missing or expired | Rerun `synapse config` |
| Download stops partway | Flaky connection | Rerun `synapse get -r`; it skips finished files |
| `qs2` read error on one chunk | Truncated file | Re-download that chunk |
| One species missing | Partial download | Rerun `synapse get -r` |
