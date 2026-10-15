# NCBI E-utilities

Base `https://eutils.ncbi.nlm.nih.gov/entrez/eutils`. Limit: 3 requests per second, 10 with
`NCBI_API_KEY`; append `&api_key=$NCBI_API_KEY` when the variable is set. Add `&tool=<name>` and
`&email=<address>` on scripted traffic. Sleep 0.34 s between calls without a key.

## Verbs

| Verb | Use |
|---|---|
| `esearch.fcgi` | query to a list of UIDs (`retmode=json`, `retmax`, `usehistory=y`) |
| `esummary.fcgi` | UIDs to short records (`retmode=json`) |
| `efetch.fcgi` | UIDs or accessions to full records (`rettype=fasta`, `gb`, `xml`) |
| `elink.fcgi` | UIDs to linked UIDs in another database (`dbfrom`, `db`, `cmd=neighbor`) |
| `einfo.fcgi` | databases and searchable fields |

Databases used here: `gene`, `protein`, `nuccore`, `pubmed`, `taxonomy`, `pccompound`,
`pcsubstance`, `biosystems`, `snp`, `clinvar`.

## Calls

Pass `-g` to curl: it otherwise expands the `[sym]` and `[orgn]` brackets as ranges and sends
an empty request.

| Task | Call |
|---|---|
| Mouse gene by symbol | `esearch.fcgi?db=gene&term=Akt1[sym]+AND+Mus+musculus[orgn]&retmode=json` |
| Gene record | `esummary.fcgi?db=gene&id=11651&retmode=json` |
| RefSeq protein FASTA | `efetch.fcgi?db=protein&id=NP_001396378.1&rettype=fasta&retmode=text` |
| Transcript FASTA (accession from `esummary` on the gene's `nuccore` links) | `efetch.fcgi?db=nuccore&id=NM_[accession]&rettype=fasta&retmode=text` |
| Gene to proteins | `elink.fcgi?dbfrom=gene&db=protein&id=11651&retmode=json` |
| Gene to PubMed | `elink.fcgi?dbfrom=gene&db=pubmed&id=11651&retmode=json` |
| PubMed to proteins | `elink.fcgi?dbfrom=pubmed&db=protein&id=<PMID>&retmode=json` |
| Compound name to PubChem UID | `esearch.fcgi?db=pccompound&term=glucose[Name]&retmode=json` |
| Taxon ID of a name | `esearch.fcgi?db=taxonomy&term=Mus+musculus[Scientific+Name]&retmode=json` |

## Search qualifiers

`[sym]` gene symbol, `[Gene Name]`, `[orgn]` organism, `[Organism]`, `[Accession]`, `[SLEN]`
sequence length, `[Properties]` (`patent[Properties]`, `srcdb_refseq[Properties]` restricts to
RefSeq), `[Filter]`, `[Title/Abstract]`, `[MeSH Terms]`.

## Sequence retrieval cascade

1.  Accession in hand: `efetch` `protein` or `nuccore`.
2.  Nucleotide record with a CDS: `efetch` `rettype=fasta_cds_aa` returns the translated CDS.
3.  Gene symbol and organism: `esearch` `protein` with `[Gene Name]` and `[Organism]`.
4.  PubMed-linked sequence: `elink` `pubmed` to `protein`.
5.  Choose among hits by length against the expected length, header match, and source:
    RefSeq before GenPept before patent records.

Accession prefixes: `NM_`, `NR_` RefSeq transcript; `NP_`, `XP_` RefSeq protein; `NC_` genome
scaffold; `ENS...` is Ensembl and `P`, `Q`, `O` + digits is UniProt, which belong to other
databases.

## Reading results

-   `esearch` returns UIDs, which differ from accessions; `esummary` or `efetch` reveals the
    accession.
-   A gene UID is the NCBI Gene ID that KEGG `mmu:` entries use.
-   A response with `count: 0` is a result; widen the qualifier before changing databases.
-   Genomic records (`NC_`, `NT_`) hold no mature CDS; fetch the transcript.

Upstream: https://www.ncbi.nlm.nih.gov/books/NBK25499/; policies
https://www.ncbi.nlm.nih.gov/home/about/policies/
