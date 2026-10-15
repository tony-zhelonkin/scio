# Mapping metabolomics and spatial metabolomics features to compounds

The unit of evidence is an observed m/z, with an optional MS/MS spectrum and an optional
retention time. A database match is a candidate set whose size depends on how many compounds
share the mass, so every annotation keeps its candidate count and its confidence level.

## Pipeline

```
m/z + polarity + adduct list --> neutral mass window --> KEGG and PubChem candidates
   --> collapse stereo (InChIKey block 1) --> restrict to the biological context
   --> assign confidence level --> attach pathway and enzyme context
```

### 1. Neutral mass from m/z

For a singly charged ion, `M = m/z - delta`, with delta from the adduct:

| Mode | Adduct | delta (Da) |
|---|---|---|
| positive | `[M+H]+` | +1.007276 |
| positive | `[M+Na]+` | +22.989221 |
| positive | `[M+K]+` | +38.963158 |
| positive | `[M+NH4]+` | +18.033826 |
| positive | `[M+H-H2O]+` | -17.003289 |
| negative | `[M-H]-` | -1.007276 |
| negative | `[M+Cl]-` | +34.969401 |
| negative | `[M+FA-H]-` | +44.998203 |

Window: `half_width = M * ppm * 1e-6`. Orbitrap and FT-ICR data support 3 to 5 ppm; MALDI-TOF
imaging often needs 10 to 20 ppm. Set the window from the instrument's calibration residuals.
Evaluate every adduct for the polarity, because one m/z gives one candidate set per adduct.

### 2. Candidate search

```bash
python3 -I scripts/kegg_rest.py find compound 180.0630-180.0640 exact_mass     # KEGG
curl -s "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/exact_mass/range/180.063/180.064/cids/JSON"   # PubChem
```

KEGG holds about 19,700 compound entries (19,666 at the 2026-10-14 release) with pathway context; PubChem holds
over 100 million structures with little biological filtering. Search KEGG first for a
biological annotation; use PubChem to extend to lipids, drugs and exogenous chemicals, then
filter by KEGG or ChEBI membership to restore context.

Verified: the window `180.0630-180.0640` returns `C00031` glucose, `C00095` fructose,
`C00124` galactose, `C00137` and more, all at 180.063388. Mass alone cannot choose among them.

Formula search (`find compound C6H12O6 formula`) is the right call after an isotope pattern
or an MS/MS-derived formula has fixed the composition.

### 3. Restrict to biology

For a mouse experiment keep candidates that satisfy at least one of:

-   linked to a KEGG reaction (`link reaction cpd:C#####` returns rows),
-   linked to a pathway present in `mmu` (`link pathway cpd:C#####` intersected with
    `list pathway mmu`),
-   in a curated list the project supplies (a panel, a diet, a medium).

Report how many candidates each filter removed. Exogenous compounds (media, drugs, plasticisers,
solvents) are real signals; a filter that discards them states its own premise.

### 4. Confidence levels

Use the Schymanski et al. (2014, Environ. Sci. Technol.) scale, which fits both LC-MS and
imaging:

| Level | Evidence | Wording |
|---|---|---|
| 1 | reference standard matched on MS/MS and retention time | "confirmed" |
| 2 | library or diagnostic MS/MS match | "probable" |
| 3 | candidate structure from mass, formula and context | "tentative candidate" |
| 4 | unambiguous formula | "formula" |
| 5 | exact mass only | "mass of interest" |

An imaging dataset without MS/MS sits at level 4 or 5; naming a single compound claims
level 2 or higher and needs the spectrum.

### 5. Context for each annotation

For each retained candidate: pathways (`link pathway cpd:`), reactions (`link reaction cpd:`),
the K numbers of those reactions (`link ko rn:`), and the mouse genes of those K numbers
(`link mmu ko:`). This table joins the metabolite layer to the gene layer.

## Spatially resolved metabolomics

-   **One annotation per ion image.** The unit is the m/z bin (centroid within its ppm window),
    so an annotation table has one row per bin with its candidate list.
-   **Adduct families.** An ion image at m/z X and another at X + 21.98 (Na minus H) with
    correlated spatial patterns suggest one compound; check the correlation before merging.
-   **Isobars.** Resolve with higher mass resolution, ion mobility or on-tissue MS/MS; a
    database cannot.
-   **Matrix peaks.** Remove MALDI matrix ions and their adducts before annotation; they match
    metabolites by chance.
-   **Region-level reporting.** When regions of interest are aggregated, annotate the aggregate
    feature table once, then carry the annotation to all regions.
-   **Gene-side partner.** The spatial transcriptome or bulk RNA of the same tissue enters
    through [rna-metabolite-prediction.md](rna-metabolite-prediction.md).

## Targeted panels

A panel arrives with names. Resolve each name to candidates (`pubchem-pug.md`), pick the
candidate by stereo and charge state matching the standard, then convert to KEGG, ChEBI and
InChIKey (`id-conversion.md`). Keep the original panel name in its own column.

## Output table (one row per feature-candidate pair)

`feature_id`, `mz`, `polarity`, `adduct`, `neutral_mass`, `ppm_error`, `kegg_id`, `pubchem_cid`,
`inchikey`, `formula`, `candidate_n`, `filter_applied`, `confidence_level`, `pathways`.

## Verification

-   Recompute the neutral mass of one retained candidate from its formula and compare it to
    `neutral_mass` within the window.
-   Count candidates per feature and report the median and the share with exactly one.
-   Spot-check three annotations against an independent source (PubChem record or a standard).
