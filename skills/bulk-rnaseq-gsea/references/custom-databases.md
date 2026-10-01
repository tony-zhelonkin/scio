# Custom gene-set databases

Every source becomes a `gs_db` and joins the `dbs` list under the project's key. From there the
compute, figure and master steps in `../SKILL.md` apply unchanged. Contracts: `?gsdb_from_file`,
`?gsdb_register`, `?gsdb_load`.

## Source to provider

| Source | Call |
|---|---|
| Bundled: `mitopathways`, `mitoxplorer`, `mito_unified`, `transportdb` | `gsdb_load(database, species = sp)` |
| GMT or GMX file | `gsdb_from_file(path, database = "MyDB", species = sp, prefix = "MYDB")` |
| Long table, one row per gene per set | `gsdb_register(split(df$gene, df$set), database = "MyDB", species = sp, pathway_names = nm)` |
| GATOM module (`igraph`) | `gsdb_register(list(GATOM_<THEME> = gatom_genes(m)), database = "GATOM", species = sp)` |
| CoReSh-derived sets | `gsdb_coresh()`: skill `coresh-signature-search` |

`gsdb_info(database)` returns citation and provenance for a bundled database. Use a bundled
database over a project copy of the same source.

## Conventions

- **Set ids carry an upper-case database prefix:** `MYDB_<set>`. `gsdb_from_file(prefix = )` adds
  it; for `gsdb_register()` build it into the list names.
- **`database` is the join key; `database_label` is display text.** Set the key to the project's
  name for the source.
- **Symbols match the target species before registration.** `species` records what the symbols
  are; it maps nothing.
- **Leave `min_size` and `max_size` at `NULL` on the provider.** `gs_test()` applies 10 to 500.
- **A GATOM module is one set.** Its genes come from the graph edges via `gatom_genes()`. A module
  below 10 genes needs its own `min_size` on that `gs_test()` call, recorded in the stage config.

## Identifiers

| Input | Route |
|---|---|
| Symbols of the target species | register directly; trim whitespace, drop `NA` |
| Entrez ids, same species | `entrez_to_gene(ids, species = "mouse")` |
| Ensembl or RefSeq ids, same species | `AnnotationDbi::mapIds(org.Mm.eg.db, keys, "SYMBOL", keytype)`; strip RefSeq version suffixes (`sub("\\.\\d+$", "", id)`) first |
| Human symbols, mouse analysis | ortholog map before registration (`homologene::homologene(x, inTax = 9606, outTax = 10090)`); title-case the misses and keep those present in `org.Mm.eg.db`, which recovers `mt-` genes |
| Human MSigDB | `gsdb_msigdb(sp, db_species = "HS")` maps internally |

## Merging sources

Collapse near-identical sets across merged sources at Jaccard ≥ 0.99, keeping the preferred
source's id. `mito_unified` is MitoPathways and mitoXplorer merged this way.

## Checks

```r
db <- dbs$MyDB
summary(db)                                                   # sets and sizes
mean(unique(unlist(db)) %in% names(ranks[[1]]))               # above 0.5
all(startsWith(names(db), "MYDB_"))
```

Overlap below 0.3 means an identifier or species mismatch. Fix it before testing.

Replacing a project file with a bundled provider is a data substitution. Compare against what the
old path produced, after three reconciliations:

1. **Parse GMX by column.** Row 1 holds set names, row 2 descriptions, rows 3 onward genes.
   `gsdb_from_file()` does this.
2. **Match on the leaf name.** `mitopathways` ids are dot-joined hierarchy paths
   (`MITOPATHWAYS_Metabolism.Amino_acid_metabolism`).
3. **Case-fold symbols** when the two sides differ in species.

Bundled `mitopathways` for mouse is a superset of the old human-to-mouse conversion; expect NES
and padj to shift for the sets it enlarges.
