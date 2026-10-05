---
name: gatom-metabolomic-predictions
description: "GATOM metabolic modules via bulkiRNA (>= 1.2.0): finds the maximally regulated metabolic subnetwork from DE results via atom-transition graphs and BUM-scored SGMWCS. Use to read transcriptomic or metabolomic DE through KEGG, Rhea, combined or lipid reactions. Needs raw p-values. For pathway enrichment use bulk-rnaseq-gsea."
license: MIT
---

# GATOM: active metabolic modules

GATOM scores a metabolic graph with a beta-uniform mixture (BUM) and solves for the
maximum-weight connected subgraph. The module is a scored optimum; it carries no permutation
p-value. GATOM is three calls, and bulkiRNA wraps each as one layer that records what it did on
its result. Read `skills/bulkirna` for the DE fit.

```
gatom_refs() + gatom_de()  ->  gatom_graph()  ->  gatom_score()  ->  gatom_solve()
                                                                    gatom_solver()
gatom_module() = the three layers in order       gatom_genes(), gatom_pathways() read a module
```

## Rules this skill imposes

1. **Feed raw p-values from the unfiltered DE table.** BUM is fitted to the whole p-value
   distribution. `gatom_de()` rejects an adjusted-looking column and values outside `[0, 1]`.
2. **Give `baseMean` as any expression measure.** gatom only ranks genes by it and keeps the top
   12,000; `AveExpr` and `2^AveExpr` give the same graph. Report `attr(g, "genes_kept")`.
3. **Read genes from edges.** `gatom_genes()` returns edge gene symbols for every id type.
4. **Run the k sensitivity branches.** `k_gene` sets the gene threshold at the k-th smallest
   p-value, capped at FDR 0.1: a larger k grows the module. Run 25, 50 and 75 on one graph, and
   report the module size per k and the shared core.
5. **Keep `seed = 42`.** It is the vignette's seed and reproduces the historical modules.
6. **Use the exact solver for reported modules.** `gatom_solver("virgo")` is the authors'
   recommendation; it needs CPLEX at `CPLEX_HOME`. `"rnc"` is the vignette's heuristic for
   exploration. Report `attr(m, "solver")` and `attr(m, "solved_to_optimality")`.
7. **Report the run from the module.** Every module carries its network, topology, gene counts,
   BUM fit, k, seed, solver and solution weight as attributes. Save them with the module.

## Task → export

| Task | Export |
|---|---|
| Fetch network files and `SHA256SUMS` | `gatom_download_refs(dir, species, networks, overwrite)` |
| Load and verify one network's references | `gatom_refs(species, dir, network = "kegg" \| "rhea" \| "combined" \| "lipids")` |
| Build the gene DE input | `gatom_de(x, id, pval, log2FC, baseMean)` |
| Build the graph | `gatom_graph(de, refs, topology, met_de, keep_reactions_without_enzymes)` |
| Score it | `gatom_score(g, k_gene, k_met, seed)` |
| Choose the solver | `gatom_solver("rnc")`, `gatom_solver("virgo", cplex_dir, threads, penalty, timelimit)` |
| Solve for the module | `gatom_solve(gs, solver, seed)` |
| All three in one call | `gatom_module(de, refs, k_gene, k_met, met_de, seed, solver, topology = ...)` |
| Module genes | `gatom_genes(m)` |
| Pathway annotation | `gatom_pathways(m, refs, universe, min_size, collapse)` |
| Interactive HTML | `gatom_save_html(m, path, name)` |

## Recipe

```r
refs_dir <- "00_data/references/gatom"
gatom_download_refs(dir = refs_dir, species = "Mus musculus",
                    networks = c("kegg", "combined"))         # one-time, networked
refs <- gatom_refs("Mus musculus", dir = refs_dir, network = "combined")
print(refs)                                                    # files and "(verified)"

de <- gatom_de(tt, id = Symbol, pval = P.Value, log2FC = logFC, baseMean = AveExpr)
g  <- gatom_graph(de, refs)                                    # reports genes kept
solver <- gatom_solver("virgo")                                # or gatom_solver("rnc")

mods <- lapply(c(25, 50, 75), function(k) {
  gatom_solve(gatom_score(g, k_gene = k, seed = 42), solver, seed = 42)
})
names(mods) <- paste0("k", c(25, 50, 75))
sapply(mods, attr, "n_edges")                                  # module size per k
core <- Reduce(intersect, lapply(mods, gatom_genes))           # interpret these first

pw <- gatom_pathways(mods$k50, refs)                           # fora + collapse, as the vignette
gatom_save_html(mods$k50, "03_results/<stage>/plots/GATOM/combined_k50.html",
                name = "<contrast>: combined, k = 50")
```

Build the graph once and score it per k. Treat a gene present at one k only as a size effect.

## What a module records

| Attribute | Meaning |
|---|---|
| `network`, `topology`, `species` | the reference set and graph shape |
| `genes_in_de`, `genes_kept`, `graph_genes` | the 12,000-gene cut-off and the annotation universe |
| `k_gene`, `gene_threshold`, `gene_bum_alpha`, `gene_fdr` | the scoring and its BUM fit (`met_*` likewise) |
| `solver`, `solver_params`, `seed` | how it was solved |
| `solution_weight`, `solved_to_optimality` | the objective and whether it is proven optimal |

`gene_threshold` and `gene_bum_alpha` are exact. `gene_fdr` has six decimals; `0` means below
`5e-7`.

## Networks

| `network` | Content | Topology |
|---|---|---|
| `"kegg"` | KEGG reactions | `"atoms"` |
| `"rhea"` | Rhea reactions | `"atoms"` |
| `"combined"` | KEGG + Rhea + BiGG transport | `"atoms"` |
| `"lipids"` | Rhea lipid subnetwork | `"metabolites"`, as the vignette recommends |

`gatom_refs()` loads the network's `gene2reaction` table with it.

## The exact solver

CPLEX is IBM-licensed and mounted into the container read-only at `/opt/cplex`, with
`CPLEX_HOME=/opt/cplex`. A dev container gets both from `init-project.sh --cplex <dir>`; a
throwaway container from `-v <dir>:/opt/cplex:ro -e CPLEX_HOME=/opt/cplex`. `gatom_solver("virgo")`
stops with a message naming `CPLEX_HOME` when the mount is missing. To compare solvers, solve the
same scored graph with each and compare `solution_weight`, module size and genes.

## Metabolite DE (`met_de`)

Pass a metabolite table as `met_de` with an ID column, raw `pval` and `log2FC`, and set `k_met`.
For metabolite data alone, pass `de = NULL` and `k_gene = NULL`. `met_de$ID` matches the `met.db`
base ID or any `refs$met_db$mapFrom` type: KEGG, HMDB or ChEBI for KEGG; KEGG or ChEBI for
combined. HMDB exists as 5-digit (`HMDB00634`) and 7-digit (`HMDB0000008`) accessions; compare a
few `refs$met_db$mapFrom` IDs against `met_de$ID` before solving.

## Reading a module

- Colour and read **edges** by `log2FC`. Vertices carry metabolite scores.
- State network, species, `k_gene`, seed and solver with every module figure and table.

## Pitfalls

| Symptom | Cause and fix |
|---|---|
| `do not fit a beta-uniform mixture` | The p-values are pre-filtered, adjusted or uninformative. Use the full table's raw p-values. |
| `The metabolic graph has no edges` | `id` holds an id type the annotation lacks. Use symbols, Entrez, Ensembl or RefSeq. |
| `cplex_dir is empty` | `CPLEX_HOME` points at no CPLEX. Add the `/opt/cplex` mount and `CPLEX_HOME`. |
| `do not match its SHA256SUMS` | A reference file changed. Refetch with `overwrite = TRUE`. |
| `met_de` matches few metabolites | ID-format mismatch. Inspect `refs$met_db` IDs. |
| `gatom_save_html()` fails on pandoc | Install pandoc or set `RSTUDIO_PANDOC`; the error names the fix. |

## Stage layout

Compute in `2.x_gatom.R`; render in `3.x_gatom_viz.R`. Rendering reads the saved module.

## See also

- `bulkirna` — DE fit and the general recipe
- `bulk-rnaseq-gsea` — pathway enrichment statistics
- `genenmf-metaprogram-discovery`

Upstream: the gatom vignette (`vignette("gatom-tutorial", package = "gatom")`) and
http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/
