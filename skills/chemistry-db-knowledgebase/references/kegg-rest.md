# KEGG REST

Base `https://rest.kegg.jp`. Seven operations; every one goes through
`scripts/kegg_rest.py` (3 calls per second ceiling, shared across processes, stops on 403).

```bash
python3 -I scripts/kegg_rest.py <op> <args...> [--option FMT] [--json] [-o FILE]
```

An argument `@ids.txt` reads one entry per line. `get`, `conv` and `link` split a long list into
batches of 10 joined by `+`.

## Operations

| Op | Form | Returns |
|---|---|---|
| `info` | `info pathway` | release and entry counts |
| `list` | `list pathway mmu`, `list compound`, `list organism` | `id<TAB>name` rows |
| `find` | `find compound glucose`; `find compound C6H12O6 formula`; `find compound 180.063-180.064 exact_mass`; `find compound 180-181 mol_weight` | `id<TAB>name` or `id<TAB>value` rows |
| `get` | `get cpd:C00031`; `get mmu:11651 --option aaseq`; `get mmu00010 --option kgml` | flat entry, sequence, MOL, KGML, JSON, PNG |
| `conv` | `conv ncbi-geneid mmu`; `conv uniprot mmu:11651`; `conv chebi cpd:C00031` | `source<TAB>target` rows |
| `link` | `link ko mmu:11651`; `link reaction ko:K00844`; `link compound mmu00010` | `source<TAB>target` rows |
| `ddi` | `ddi D00001 D00002` | drug interaction rows (Japanese labels) |

`--option` values for `get`: `aaseq`, `ntseq`, `mol`, `kcf`, `image` (needs `-o`), `kgml`, `json`.
`image`, `kgml` and `json` take exactly one entry.

## Databases

`pathway`, `module`, `ko`, `genome`, `genes`, `compound`, `glycan`, `reaction`, `rclass`,
`enzyme`, `network`, `variant`, `disease`, `drug`, `dgroup`, `brite`, and any organism code
(`mmu` mouse, `hsa` human, `rno` rat). `list organism` lists the codes.

## Entry prefixes

`cpd:` compound, `gl:` glycan, `rn:` reaction, `ko:` orthology, `ec:` enzyme, `path:` pathway,
`md:` module, `dr:` drug, `ds:` disease. Bare `C00031`, `R00299` and `K00844` resolve; gene
entries always carry the organism: `mmu:11651`.

## Link graph that answers metabolic questions

```
gene (mmu:ID) <-> ko <-> reaction (rn) <-> compound (cpd)
      |            |          |               |
   pathway      pathway    pathway         pathway
      \__ enzyme (ec) joins gene, ko and reaction __/
```

| Question | Call |
|---|---|
| K numbers of a gene | `link ko mmu:11651` |
| Genes carrying a K number in mouse | `link mmu ko:K04456` |
| Reactions of a K number | `link reaction ko:K00844` |
| Compounds in a reaction | `link compound rn:R00299` |
| Reactions of a compound | `link reaction cpd:C00031` |
| Pathways of a compound, gene or reaction | `link pathway cpd:C00031` |
| Genes in a mouse pathway | `link mmu mmu00010` |
| Compounds in a mouse pathway | `link compound mmu00010` |
| Enzymes of a gene | `link enzyme mmu:11651` |

Run one call per question and read the row count. A `link` with no rows is an answer: the
entry has no link of that kind.

## Conversion targets

`conv` knows `ncbi-geneid`, `ncbi-proteinid`, `uniprot` (rows come back prefixed `up:`),
`pubchem` (SIDs, prefixed `pubchem:`), `chebi` (prefixed `chebi:`), and organism codes for the
reverse direction (`conv mmu ncbi-geneid:11651`). A whole-database conversion
(`conv ncbi-geneid mmu`) is one call and is the cheapest route for a table of genes.

## Reading a compound entry

`get cpd:C00031` returns labelled blocks: `NAME`, `FORMULA`, `EXACT_MASS`, `MOL_WEIGHT`,
`REMARK` (`Same as: D00009` ties a compound to a drug entry), `COMMENT` (stereo variants such as
alpha-D-glucose `C00267`), `REACTION`, `PATHWAY`, `MODULE`, `ENZYME`, `DBLINKS` (CAS, PubChem
SID, ChEBI, other databases). Parse by block label.

## Pathway files

`get mmu00010 --option kgml` gives the pathway graph (entries, relations, reactions);
`--option json` gives a layout for one pathway; `--option image -o out.png` gives the drawing.
Colouring a map by data is the job of KEGG Mapper, a web tool.

## Errors

| Status | Meaning | Action |
|---|---|---|
| 200 with empty body | no match | report an empty result |
| 400 | syntax, or more than 10 entries | check spelling; use the wrapper |
| 404 | unknown entry or database | check the prefix and organism code |
| 403 | blocked | stop all KEGG traffic and wait before trying again |

Upstream documentation: https://www.kegg.jp/kegg/rest/keggapi.html
