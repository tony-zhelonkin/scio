# RNA-based metabolite and reaction predictions

An RNA-based prediction reads enzyme-gene expression as evidence about reaction capacity. The
identifier plumbing is gene to K number to reaction to compound. The result is a hypothesis
about pathway activity; metabolite abundance needs a measurement.

## Gene to compound table

```
Ensembl gene --(strip version)--> UniProt --> KEGG mmu:ID (= NCBI Gene ID)
   --link ko--> K number --link reaction--> rn --link compound--> cpd
```

Steps and calls are in [id-conversion.md](id-conversion.md) and [kegg-rest.md](kegg-rest.md).
Build the table once per annotation release and store it with its release date (`info kegg`
prints the KEGG release; `x-uniprot-release` is a response header).

| Column | Content |
|---|---|
| `gene_id` | Ensembl gene without version |
| `ncbi_gene_id` | KEGG `mmu:` number |
| `ko` | K number or empty |
| `reaction` | R number |
| `compound` | C number |
| `role` | `substrate` or `product`, from the reaction entry's `EQUATION` |
| `n_genes_for_reaction` | number of mouse genes sharing the reaction |

Row counts to report: genes with a K number, genes with a reaction, reactions per gene, genes
per reaction.

## Interpretation limits

-   **Expression is a proxy.** mRNA level reflects capacity; flux depends on substrate supply,
    allosteric control and post-translational state.
-   **Many-to-many.** One reaction has several isozymes and one enzyme has several reactions;
    aggregate a reaction by the member genes with explicit rules (the maximum for isozymes, the
    minimum for complex subunits) and write the rule down.
-   **Currency metabolites.** `C00001` water, `C00002` ATP, `C00008` ADP, `C00003` NAD+,
    `C00004` NADH, `C00005` NADPH, `C00006` NADP+, `C00009` phosphate, `C00010` CoA, `C00011`
    CO2, `C00013` diphosphate, `C00014` ammonia and `C00080` H+ occur in hundreds of reactions
    and link everything to everything. Drop them from paths and from per-compound summaries.
-   **Direction.** A KEGG reaction is drawn in one direction; reversibility needs the enzyme's
    literature. Use the reaction's substrate and product sides as an unordered pair unless
    direction is established.
-   **No compartments.** KEGG pathways carry no subcellular compartment; mitochondrial and
    cytosolic isozymes share a reaction.
-   **Orthology is inferred.** A K number is an automated assignment by sequence; paralog
    functional divergence is invisible to it.
-   **Absent from KEGG is not absent from biology.** A gene without a K number may still be an
    enzyme.

## Choosing the analysis

| Aim | Tool |
|---|---|
| Which KEGG pathways change | `bulk-rnaseq-gsea` over `mmu` pathway gene sets |
| Which connected subnetwork of reactions and metabolites changes, from gene and optional metabolite DE | `gatom-metabolomic-predictions` |
| Gene lists for a pathway of interest | `link mmu mmu00010` in [kegg-rest.md](kegg-rest.md) |
| Predicted metabolite changes to compare with measured metabolomics | build the table above, then compare directions in a shared reaction or pathway |
| Joint latent structure of RNA and metabolites | `factor-analysis-framework` |

## Comparing RNA predictions with measured metabolites

1.  Convert both sides to KEGG C numbers (measured features through
    [metabolomics-mapping.md](metabolomics-mapping.md)).
2.  Restrict to compounds present on both sides and to non-currency compounds.
3.  Compare at the pathway or reaction level; the unit of agreement is the pathway.
4.  Report the number of compounds, reactions and genes contributing to each comparison.
5.  Treat disagreement as information: post-transcriptional control, pool sizes, transport,
    and annotation ambiguity each produce it.

## Verification

-   Pick one reaction with a single mouse gene and trace it through every column.
-   Confirm that the share of DE genes with a K number approximates the share in the whole
    expressed set; a large gap points to a mapping failure.
-   Check that no currency compound dominates the top of a compound ranking.
