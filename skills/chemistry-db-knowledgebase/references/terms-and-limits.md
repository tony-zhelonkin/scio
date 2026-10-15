# Terms of use, rate limits and citations

This skill's code and prose are Apache-2.0. Each database has its own data terms, which bind the
user of the data. Check the pages below, and say in the first reply that uses a database which
one it was.

| Database | Terms | Notes |
|---|---|---|
| KEGG | https://www.kegg.jp/kegg/legal.html and https://www.kegg.jp/kegg/rest/ | The REST API is for academic use; non-academic use needs a licence from the KEGG copyright holder. Limit 3 calls per second; an address that exceeds it is blocked. |
| PubChem | https://pubchem.ncbi.nlm.nih.gov/docs/citation-guidelines and https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest | 5 requests per second, 400 per minute, 300 seconds of server time per minute. Records are open; individual sources keep their own terms. |
| UniProt | https://www.uniprot.org/help/license and https://www.uniprot.org/help/api_queries | CC BY 4.0 data. |
| NCBI | https://www.ncbi.nlm.nih.gov/ and https://www.ncbi.nlm.nih.gov/home/about/policies/ | 3 requests per second without an API key, 10 with. Large jobs belong off peak hours (weekends, or 9 pm to 5 am US Eastern). |

## Notification file

On first use of each database in a workspace, create `.licenses/<database>_LICENSE.txt` at the
workspace root with the sentence shown to the user and a UTC timestamp, for example:

```
kegg: Told the user on 2026-10-14T12:00:00Z to review https://www.kegg.jp/kegg/legal.html;
the KEGG REST API is licensed for academic use.
```

Skip creation when the file exists.

## Citations

| Resource | Reference |
|---|---|
| KEGG | Kanehisa M, Goto S. KEGG: Kyoto Encyclopedia of Genes and Genomes. Nucleic Acids Res 28:27-30 (2000); Kanehisa M et al. KEGG: biological systems database as a model of the real world. Nucleic Acids Res 53:D672-D677 (2025) |
| PubChem | Kim S et al. PubChem 2025 update. Nucleic Acids Res 53:D1516-D1525 (2025) |
| UniProt | The UniProt Consortium. UniProt: the Universal Protein Knowledgebase in 2025. Nucleic Acids Res 53:D609-D617 (2025), doi:10.1093/nar/gkae1010 |
| NCBI | Sayers EW et al. Database resources of the National Center for Biotechnology Information. Nucleic Acids Res (annual issue) |
| Identification levels | Schymanski EL et al. Identifying small molecules via high resolution mass spectrometry: communicating confidence. Environ Sci Technol 48:2097-2098 (2014) |

Confirm volume and page numbers against the publisher before they enter a manuscript.

## Request hygiene

-   Send `tool` and `email` parameters to NCBI on scripted traffic.
-   Cache every response in the analysis workspace; a rerun reads the cache.
-   Record the date and release of each database next to the table that used it.
-   Keep `NCBI_API_KEY` in the environment; never commit it.
-   In a batch loop, stop on the first 403 or 429 and report it.
