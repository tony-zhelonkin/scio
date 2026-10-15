# Cross-database identifier conversion

Each conversion has one owning route. The count of candidates at every hop travels with the
identifier: `1`, `n` or `0`.

## Route table

| From | To | Route |
|---|---|---|
| KEGG gene `mmu:ID` | NCBI Gene ID | strip the prefix; they are the same number |
| NCBI Gene ID | KEGG gene | prefix `mmu:` |
| NCBI Gene ID, many | KEGG | `kegg_rest.py conv mmu ncbi-geneid:ID1 ncbi-geneid:ID2 ...` or whole-set `conv ncbi-geneid mmu` |
| KEGG gene | UniProt | `kegg_rest.py conv uniprot mmu:ID` (rows `up:ACC`) |
| UniProt | KEGG gene | UniProt job `UniProtKB_AC-ID` to `KEGG` (rows `mmu:ID`) |
| UniProt | NCBI Gene ID | UniProt job `UniProtKB_AC-ID` to `GeneID` |
| Ensembl gene | UniProt | strip the version suffix, then job `Ensembl` to `UniProtKB-Swiss-Prot` (add `UniProtKB` to include unreviewed) |
| Ensembl gene | NCBI Gene ID or KEGG | two hops: Ensembl to UniProt, then UniProt to `GeneID` or `KEGG` |
| Gene symbol | UniProt | search `gene_exact:<symbol> AND organism_id:10090 AND reviewed:true` |
| Gene symbol | NCBI Gene ID | `esearch` `db=gene` `<symbol>[sym] AND Mus musculus[orgn]` |
| NCBI Gene ID | RefSeq protein | `elink` `dbfrom=gene` `db=protein` |
| RefSeq protein | UniProt | job `RefSeq_Protein` to `UniProtKB` |
| Gene (KEGG) | K number | `link ko mmu:ID` |
| K number | mouse genes | `link mmu ko:K#####` |
| K number | reactions | `link reaction ko:K#####` |
| EC number | reactions | `link reaction ec:1.1.1.1` |
| KEGG compound | PubChem SID | `conv pubchem cpd:C#####` |
| PubChem SID | PubChem CID | PUG `substance/sid/<SID>/cids/JSON` |
| PubChem CID | InChIKey, formula, SMILES | PUG `compound/cid/<CID>/property/InChIKey,MolecularFormula,IsomericSMILES/JSON` |
| KEGG compound | ChEBI | `conv chebi cpd:C#####` (rows `chebi:ID`) |
| ChEBI | KEGG compound | `conv compound chebi:ID` |
| KEGG compound | HMDB, LIPID MAPS | `DBLINKS` block in `get cpd:C#####`, else PubChem synonyms filtered by pattern |
| CID | KEGG compound | PUG synonyms filtered by `^C\d{5}$`, or CID to SID to KEGG |
| InChIKey | CID | PUG `compound/inchikey/<key>/cids/JSON` |
| Name | CID | PUG `compound/name/<name>/cids/JSON` (candidates) |
| Name | KEGG compound | `find compound <name>` (candidates) |
| Formula or exact mass | KEGG compound | `find compound <formula> formula`; `find compound <lo>-<hi> exact_mass` |

## Worked example: glucose

```
C00031 --conv pubchem--> pubchem:3333 (SID) --PUG sid/3333/cids--> CID 5793
CID 5793 --PUG property--> WQZGKKKJIJFFOK-GASJEMHNSA-N, C6H12O6
C00031 --conv chebi--> chebi:4167      (PubChem synonyms for CID 5793 also list CHEBI:17234, CHEBI:17634)
```

Three ChEBI identifiers for one compound is normal: ChEBI keeps separate entries for open,
cyclic and stereo-specific forms. Keep all of them.

## Cardinality rules

-   A KEGG gene has zero to several K numbers; a K number has dozens of genes across mouse
    paralogs.
-   A gene maps to several UniProt accessions when unreviewed fragments exist: Ensembl
    `ENSMUSG00000001729` returns four accessions through `UniProtKB`. Restrict to
    `UniProtKB-Swiss-Prot` or `reviewed:true` and say which restriction applied.
-   A KEGG compound maps to one SID but a PubChem CID can have many KEGG compounds (stereo
    variants and generic forms); count both directions.
-   Direct Ensembl to `GeneID` is an invalid UniProt combination; the route is two hops.
-   Versioned Ensembl IDs (`ENSMUSG00000001729.12`) fail in a UniProt job; strip after the dot.

## Collapsing stereochemistry

An InChIKey has three blocks: `WQZGKKKJIJFFOK` connectivity (14 characters),
`GASJEMHNSA` stereo and isotopes, `N` protonation. To merge stereo variants, group by the
first block. To distinguish them, compare all three. Record which rule produced a merged
identifier.

## Verification

After a conversion pass, check one known pair end to end (glucose above, or mouse Akt1:
`ENSMUSG00000001729` to `P31750` to `mmu:11651` to `K04456`), then report the share of inputs
with zero, one and several outputs.
