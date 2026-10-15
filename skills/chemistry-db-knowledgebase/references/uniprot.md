# UniProt

Base `https://rest.uniprot.org`. Datasets: `uniprotkb` (annotated, `reviewed:true` is
Swiss-Prot), `uniparc` (every sequence ever seen, `UPI...`), `uniref` (clusters),
`idmapping` (jobs), `unisave` (entry history).

## Calls

| Task | Call |
|---|---|
| One entry | `GET /uniprotkb/P31750?format=json` |
| FASTA | `GET /uniprotkb/P31750.fasta` |
| Search | `GET /uniprotkb/search?query=<q>&format=tsv&fields=<f>&size=25` |
| Count | `GET /uniprotkb/search?query=<q>&size=1` and read the `x-total-results` header |
| Bulk stream | `GET /uniprotkb/stream?query=<q>&format=tsv&fields=<f>` (no `size`, up to 10 million rows) |
| Deleted or old entry | `GET /unisave/P31750?format=json` |

Count before every search without a `size`, and prefer `stream` for bulk.

## Query syntax

-   Space is AND; `OR` must be capitalised; commas are literal.
-   Group alternatives: `accession:(P31750 OR P47196)`.
-   Quote short terms and give a field: `gene_exact:Akt1`, not `Akt1`.
-   Fields that carry most questions: `gene_exact:`, `gene:`, `protein_name:`, `accession:`,
    `organism_id:`, `reviewed:`, `ec:`, `go:`, `keyword:`, `cc_function:`, `xref:`, `length:[a TO b]`.
-   `name:` is invalid; use `protein_name:`.
-   Broad free-text searches match publication titles; use a field filter.
-   Before using a GO, keyword or Pfam ID in a query, look up its description.

Mouse protein for a symbol:

```
query=gene_exact:Akt1 AND organism_id:10090 AND reviewed:true
fields=accession,id,gene_names,protein_name,xref_kegg,xref_geneid,xref_ensembl,ec,length
```

Useful `fields`: `accession`, `id`, `gene_names`, `gene_primary`, `protein_name`,
`organism_name`, `length`, `ec`, `go_p`, `go_f`, `go_c`, `cc_function`, `cc_subcellular_location`,
`cc_catalytic_activity`, `cc_pathway`, `xref_kegg`, `xref_geneid`, `xref_ensembl`, `xref_refseq`,
`xref_chembl`, `xref_pdb`, `sequence`.

`cc_catalytic_activity` and `xref_rhea` link an enzyme to its reactions; `ec` lists EC numbers.
`xref_kegg` returns `mmu:11651;` rows to split on `;`.

## ID mapping jobs

```
POST /idmapping/run            from=<db>&to=<db>&ids=<comma list>   -> {"jobId": ...}
GET  /idmapping/status/<job>   poll every 2 s until a redirect or "results" appears
GET  /idmapping/results/<job>  JSON; add /stream for the whole set
```

| Source IDs | `from` | `to` |
|---|---|---|
| UniProt accession | `UniProtKB_AC-ID` | `KEGG`, `GeneID`, `Ensembl`, `RefSeq_Protein`, `ChEMBL`, `PDB`, `Reactome` |
| NCBI Gene ID | `GeneID` | `UniProtKB` (never `UniProtKB-AC`) |
| Ensembl gene, no version suffix | `Ensembl` | `UniProtKB-Swiss-Prot` or `UniProtKB`; `to=GeneID` is an invalid pair, so take a second hop from the accession |
| Ensembl protein | `Ensembl_Protein` | `UniProtKB` |
| RefSeq protein | `RefSeq_Protein` | `UniProtKB` |
| Gene symbol | `Gene_Name` | `UniProtKB`; may need `taxId=10090` |
| KEGG gene | `KEGG` | `UniProtKB` |

Valid pairs are listed at `GET /configure/idmapping/fields`. A job takes up to 100,000 IDs. A versioned Ensembl ID (`ENSMUSG00000001729.12`) comes back in `failedIds`; strip the suffix first. `ENSMUSG00000001729` (Akt1) returns four accessions through `UniProtKB` and one through `UniProtKB-Swiss-Prot`. A
search on `xref:` is the alternative when mapping fails: an external ID may be searchable in
UniParc yet unmappable to UniProtKB.

## Search misses

1.  Pivot from `gene:` to `protein_name:`.
2.  Search `uniparc` for sequences without an annotated entry.
3.  Resolve the human or mouse ortholog first to learn the canonical name.

## Reading results

-   An accession (`P31750`) carries annotation; a UPI carries a sequence only.
-   `reviewed:true` is curated; unreviewed entries are automatic annotation.
-   A gene can map to several accessions (isoforms, paralog families, fragments); keep the
    count with the mapping.
-   UniProtKB mouse proteome ID `UP000000589` for full proteome queries.

Upstream: https://www.uniprot.org/help/api; terms https://www.uniprot.org/help/license
