# Restartability and Data Flow

Use this guide to place durable state, define cross-stage contracts, 
and make an analysis resume from a known boundary. 

Apply CRAFT for authoritative result paths and standing reproducibility requirements. 
Use the relevant assay skill for object formats and scientific validation.

## A checkpoint is a recovery boundary

A useful checkpoint captures a completed unit of work whose inputs and meaning are understood. 
Its purpose is to resume safely after interruption, inspect an expensive intermediate, 
or hand stable state to another stage.

Choose boundaries by consequence:
- recovery would avoid meaningful compute or manual work;
- the intermediate supports a real validation decision;
- downstream work consumes it as a named state; or
- reproducing it requires an external service or scarce resource.

## Cache, checkpoint, and deliverable

Treat these as distinct responsibilities:
- A cache accelerates recomputation and may be discarded.
- A checkpoint supports recovery or a stage handoff 
  and carries enough context to decide whether reuse is valid.
- A deliverable is a reviewed output with an audience and a stable contract.

A cache is earned by expensive work. A check or step that finishes in seconds runs every time,
so it cannot go stale. Where reuse is earned, its dependency record sits in one place beside the
output (a sidecar or a header), so a committed deliverable changes only when its content does.

## Safe reuse

Before loading existing state, establish what makes it current: source data,
upstream checkpoints, consequential configuration and decisions, code or tool
versions, and the schema or object-format version.

When those inputs change, invalidate or version the dependent state. 

A force flag is useful for an operator; it does not replace dependency reasoning. 

Never delete or overwrite a valuable prior result until the replacement 
has been written and validated successfully.

## Write complete state

Prefer a write-then-rename pattern when the format and filesystem support it.
Validate the temporary output before promotion, including the invariants the next stage assumes. o
Record its inputs, consequential configuration and decisions, producer version, and completed checks.

Keep one clear writer for each authoritative handoff. 

## Cross-stage contracts

The boundary between stages should state:
- artifact identity and location through the project's path API;
- schema, dimensions, identifiers, ordering, units, and sign conventions;
- completeness conditions and allowed missingness; and
- the check a reader performs before use.

Readers validate the contract they depend on. 
They should not silently repair an upstream artifact.
Stage owning the artifact is the target for change/fix/refactor should there be the need to 
change the artifact after the stage has been passed. 

## Configuration and data boundaries

Keep revisable values in project configuration. 
Loaders may derive paths and provide typed accessors; 
helpers receive the values that affect their behavior.

A condition-dependent cutoff cannot be read from configuration, 
so a reader cannot tell which number the analysis used.

Keep raw inputs immutable. 
Write generated state to the result or scratch surface that CRAFT assigns, 
according to its lifecycle. 

## Restart verification

Verify fresh and resumed execution:

1. Run from an empty generated-state surface and confirm every handoff is created
   and checked.
2. Resume from each supported checkpoint and confirm upstream work is skipped
   only when recorded dependencies still match.
3. Change one consequential input and confirm dependent state is invalidated or
   versioned.
4. Interrupt a write when practical and confirm readers reject partial state.

`scio lint` owns its current project checks. 
Restartability remains a runtime property verified through execution.
