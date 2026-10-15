# PubChem PUG-REST

Base `https://pubchem.ncbi.nlm.nih.gov/rest/pug`. Limit: 5 requests per second and 400 per
minute; sleep 0.25 s between calls and use list inputs. Responses are JSON unless the path ends
in `CSV`, `TXT`, `SDF` or `PNG`.

## URL grammar

```
/<domain>/<namespace>/<identifiers>/<operation>/<output>[?options]
```

| Part | Values used here |
|---|---|
| domain | `compound`, `substance`, `assay`, `gene`, `protein` |
| namespace | `cid`, `sid`, `name`, `smiles`, `inchikey`, `formula`, `fastformula`, `fastidentity`, `fastsimilarity_2d`, `fastsubstructure` |
| identifiers | one value, or a comma list (`cid/5793,2244`) |
| operation | `cids`, `sids`, `property/<list>`, `synonyms`, `xrefs/<type>`, `assaysummary`, `aids`, `record` |

Spaces and special characters in names and SMILES are URL-encoded; `/`, `#` and `\` in SMILES
need it. For long SMILES or many names use POST with the identifier in the body.

## Calls that answer identifier questions

| Question | Path |
|---|---|
| Name to CID candidates | `compound/name/<name>/cids/JSON` |
| CID to formula, masses, InChIKey, SMILES | `compound/cid/5793/property/MolecularFormula,ExactMass,MonoisotopicMass,InChIKey,IsomericSMILES,IUPACName/JSON` |
| InChIKey to CID | `compound/inchikey/<key>/cids/JSON` |
| First block of an InChIKey to CIDs | no PUG namespace; fetch by full key, or compare the first 14 characters locally |
| SID to CID (after KEGG `conv pubchem`) | `substance/sid/3333/cids/JSON` |
| CID to synonyms (carry registry IDs such as `CHEBI:17234`, `C00031`, `HMDB...`) | `compound/cid/5793/synonyms/JSON` |
| CID to registry cross-references | `compound/cid/5793/xrefs/RegistryID/JSON` |
| Formula to CIDs | `compound/fastformula/C6H12O6/cids/JSON?MaxRecords=50` |
| Mass window to CIDs | `compound/exact_mass/range/180.063/180.064/cids/JSON` |
| Similar structures | `compound/fastsimilarity_2d/smiles/<smiles>/cids/JSON?Threshold=90&MaxRecords=20` |
| Substructure | `compound/fastsubstructure/smiles/<smiles>/cids/JSON?MaxRecords=20` |
| Assays for a CID | `compound/cid/<cid>/assaysummary/JSON`, `.../aids/JSON?aids_type=active` |

Property names: `MolecularFormula`, `MolecularWeight`, `ExactMass`, `MonoisotopicMass`,
`InChI`, `InChIKey`, `IsomericSMILES`, `CanonicalSMILES`, `IUPACName`, `XLogP`, `TPSA`,
`Complexity`, `HBondDonorCount`, `HBondAcceptorCount`, `RotatableBondCount`, `HeavyAtomCount`.

`xrefs/<type>` takes `RegistryID`, `RN` (CAS), `PubMedID`, `PatentID`, `GeneID`, `ProteinGI`,
`TaxonomyID`, `MMDBID`. Synonym lists are long (hundreds); filter by pattern:
`^CHEBI:\d+$`, `^C\d{5}$`, `^HMDB\d+$`, `^LMSD\w+$`, `^\d{2,7}-\d{2}-\d$` (CAS).

## Curated annotation: PUG-View

`https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/<cid>/JSON?heading=<Heading+With+Plus>`
Headings: `Safety+and+Hazards`, `Pharmacology+and+Biochemistry`, `Toxicity`,
`Drug+and+Medication+Information`, `Experimental+Properties`, `Names+and+Identifiers`.

## Bulk and asynchronous

Searches without the `fast` prefix return a ListKey to poll
(`.../compound/listkey/<key>/cids/JSON`). Prefer `fast*` namespaces for interactive work. For a
list above 100 CIDs, request properties in comma batches of 100 or less.

## Fallbacks when a name fails

-   Search the neutral parent of a salt or ion.
-   Strip hydrate and counter-ion words.
-   Query by formula, then filter by exact mass.
-   Use a structure search from a SMILES drawn for a fragment.

## Reading results

-   `compound/name` returns CIDs ordered by PubChem's ranking; the first is a candidate.
-   A CID is a standardised structure; a SID is one depositor's record. KEGG, ChEBI and HMDB
    deposit SIDs.
-   Charged, neutral and stereo-defined forms have separate CIDs; compare InChIKey blocks
    before calling two CIDs the same compound.

Upstream: https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest; citation guidance
https://pubchem.ncbi.nlm.nih.gov/docs/citation-guidelines
