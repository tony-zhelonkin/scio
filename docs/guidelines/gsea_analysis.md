# GSEA Analysis

> **Superseded.** GSEA and master tables run through the installed `bulkiRNA` package; see skill `bulkirna` and `bulk-rnaseq-gsea`.

**Module:** `gsea_analysis.md`
**Purpose:** Gene Set Enrichment Analysis patterns, database usage, and best practices

---

## 1. GSEA Fundamentals

### 1.1 When to Use GSEA vs ORA

| Method | Input | Best For |
|--------|-------|----------|
| **GSEA** | Full ranked gene list | Discovery, subtle effects |
| **ORA** | DE gene list only | Clear, strong effects |

**Recommendation:** Default to GSEA for RNA-seq. It uses all genes and is more sensitive to coordinated changes.

### 1.2 Ranking Metric

```r
# RECOMMENDED: t-statistic (accounts for variance)
ranked_genes <- de_results$t
names(ranked_genes) <- rownames(de_results)
ranked_genes <- sort(ranked_genes, decreasing = TRUE)

# Alternative: signed log p-value
ranked_genes <- -log10(de_results$P.Value) * sign(de_results$logFC)

# NOT recommended: logFC alone (ignores significance)
```

---

## 2. MSigDB Database Selection

### 2.1 Standard Collections

```r
# Comprehensive analysis uses these databases
MSIGDB_DATABASES <- list(
  H = c("H", ""),                        # Hallmark (50 gene sets)
  C2_KEGG = c("C2", "CP:KEGG"),         # KEGG pathways
  C2_REACTOME = c("C2", "CP:REACTOME"), # Reactome pathways
  C2_WIKIPATHWAYS = c("C2", "CP:WIKIPATHWAYS"),
  C5_BP = c("C5", "GO:BP"),             # GO Biological Process
  C5_MF = c("C5", "GO:MF"),             # GO Molecular Function
  C5_CC = c("C5", "GO:CC")              # GO Cellular Component
)
```

### 2.2 Database Characteristics

| Database | Size | Best For |
|----------|------|----------|
| **Hallmark (H)** | 50 sets | Overview, major pathways |
| **KEGG** | ~180 sets | Metabolic pathways |
| **Reactome** | ~1,600 sets | Signaling, detailed mechanisms |
| **GO:BP** | ~7,500 sets | Comprehensive biological processes |
| **GO:MF** | ~1,700 sets | Molecular functions |
| **GO:CC** | ~1,000 sets | Cellular localization |

### 2.3 When to Use Each

- **Start with Hallmark**: Best signal-to-noise, curated
- **Add KEGG/Reactome**: Specific pathway questions
- **GO terms**: Comprehensive discovery, but many redundant terms
- **Custom gene sets**: Domain-specific analysis (MitoCarta, TransportDB)

---

## 3. msigdbr Usage

### 3.1 Correct API Usage

```r
# CORRECT: species parameter only
msigdb_df <- msigdbr(
  species = "Mus musculus",  # or "Homo sapiens"
  category = "H"             # Collection
)

# Convert to list format for clusterProfiler
gene_sets <- split(msigdb_df$gene_symbol, msigdb_df$gs_name)
```

### 3.2 Common Errors to Avoid

```r
# WRONG: db_species parameter causes errors in some versions
msigdb_df <- msigdbr(
  db_species = "MM",         # DON'T USE
  species = "Mus musculus"
)

# WRONG: Invalid subcategory
msigdb_df <- msigdbr(
  species = "Mus musculus",
  category = "C2",
  subcategory = "KEGG"       # Should be "CP:KEGG"
)
```

### 3.3 Subcategory Reference

| Category | Subcategories |
|----------|---------------|
| H | (none needed) |
| C2 | CP:KEGG, CP:REACTOME, CP:WIKIPATHWAYS, CP:BIOCARTA, CGP |
| C5 | GO:BP, GO:MF, GO:CC, HPO |
| C7 | IMMUNESIGDB, VAX |
| C8 | (none needed) - cell type signatures |

---

## 4. Running GSEA

### 4.1 Using clusterProfiler

```r
library(clusterProfiler)

# Prepare ranked list
gene_list <- de_results$t
names(gene_list) <- rownames(de_results)
gene_list <- sort(gene_list, decreasing = TRUE)

# Get gene sets
msigdb_h <- msigdbr(species = "Mus musculus", category = "H")
gene_sets <- split(msigdb_h$gene_symbol, msigdb_h$gs_name)

# Run GSEA
gsea_result <- GSEA(
  geneList = gene_list,
  TERM2GENE = data.frame(
    term = msigdb_h$gs_name,
    gene = msigdb_h$gene_symbol
  ),
  pvalueCutoff = 1,        # Keep all for downstream filtering
  pAdjustMethod = "BH",
  minGSSize = 15,
  maxGSSize = 500,
  eps = 0,                 # Exact p-values
  seed = 123,
  nPermSimple = 100000     # High permutations for accuracy
)
```

### 4.2 Using fgsea (Faster)

```r
library(fgsea)

# Run fgsea
gsea_result <- fgsea(
  pathways = gene_sets,
  stats = gene_list,
  minSize = 15,
  maxSize = 500,
  nperm = 100000,          # Or use fgseaMultilevel for adaptive
  eps = 0
)
```

### 4.3 Using Toolkit Wrapper

```r
source(file.path(DIR_TOOLKIT, "scripts/GSEA/GSEA_processing/run_gsea.R"))

gsea_result <- run_gsea(
  DE_results = de_table,
  rank_metric = "t",
  species = "Mus musculus",
  collection = "H",
  subcollection = "",
  pvalue_cutoff = 1,
  padj_method = "fdr",
  nperm = 100000,
  seed = 123
)
```

---

## 5. Multi-Database GSEA Pattern

### 5.1 Parameterized Loop

```r
# Define databases to test
databases <- list(
  Hallmark = c("H", ""),
  KEGG = c("C2", "CP:KEGG"),
  Reactome = c("C2", "CP:REACTOME"),
  GO_BP = c("C5", "GO:BP")
)

# Run GSEA for each
all_results <- list()

for (db_name in names(databases)) {
  message("[GSEA] Running ", db_name, "...")

  db_params <- databases[[db_name]]

  gsea_res <- load_or_compute(
    checkpoint_file = paste0("1.3_gsea_", tolower(db_name), ".rds"),
    description = paste("GSEA", db_name),
    compute_fn = function() {
      run_gsea(
        DE_results = de_table,
        rank_metric = "t",
        species = SPECIES,
        collection = db_params[1],
        subcollection = db_params[2],
        nperm = 100000,
        seed = 123
      )
    }
  )

  all_results[[db_name]] <- gsea_res
}
```

### 5.2 Combining Results

```r
# Normalize and combine all results
combined_gsea <- bind_rows(
  lapply(names(all_results), function(db) {
    normalize_gsea_results(all_results[[db]], database = db)
  })
)
```

---

## 6. Custom Gene Sets

### 6.1 Creating Custom Gene Set Lists

```r
# From CSV file
custom_sets <- read_csv("00_data/references/custom_gene_sets.csv")
gene_set_list <- split(custom_sets$gene_symbol, custom_sets$set_name)

# From named vectors
gene_set_list <- list(
  Mitochondria = c("MT-ND1", "MT-ND2", "MT-CO1", ...),
  Glycolysis = c("HK1", "HK2", "PFKL", ...),
  Custom_Pathway = c("GENE1", "GENE2", ...)
)
```

### 6.2 Running with Custom Sets

```r
# Using fgsea
custom_gsea <- fgsea(
  pathways = gene_set_list,
  stats = gene_list,
  minSize = 10,
  maxSize = 500
)
```

---

## 7. Result Interpretation

### 7.1 Key Metrics

| Metric | Meaning | Threshold |
|--------|---------|-----------|
| **NES** | Normalized Enrichment Score | \|NES\| > 1.5 = strong |
| **pvalue** | Nominal p-value | < 0.05 |
| **padj** | FDR-adjusted p-value | < 0.05 (or 0.25 for discovery) |
| **size** | Gene set size | 15-500 optimal |
| **leadingEdge** | Core enrichment genes | Interpret biology |

### 7.2 Interpreting NES Direction

- **Positive NES**: Gene set enriched in genes UP in condition
- **Negative NES**: Gene set enriched in genes DOWN in condition

### 7.3 Filtering Results

```r
# Significant pathways
sig_pathways <- gsea_result %>%
  filter(padj < 0.05) %>%
  arrange(desc(abs(NES)))

# Top enriched (either direction)
top_pathways <- gsea_result %>%
  filter(padj < 0.05) %>%
  slice_max(abs(NES), n = 20)

# Separated by direction
up_pathways <- gsea_result %>% filter(padj < 0.05, NES > 0)
down_pathways <- gsea_result %>% filter(padj < 0.05, NES < 0)
```

---

## 8. Common Issues

### 8.1 No Significant Pathways

**Possible causes:**
- Weak biological effect
- Wrong ranking metric
- Gene symbol mismatch

**Solutions:**
1. Check DE results first (any significant genes?)
2. Verify gene symbols match MSigDB
3. Try different ranking metrics
4. Use more lenient FDR (0.1 or 0.25 for discovery)

### 8.2 Too Many Significant Pathways

**Solutions:**
1. Use Hallmark (curated, less redundant)
2. Apply stricter FDR cutoff
3. Use GSEA leading edge analysis to find core genes
4. Group redundant pathways by gene overlap

### 8.3 Gene Symbol Mismatches

```r
# Check overlap
msigdb_genes <- unique(msigdb_df$gene_symbol)
de_genes <- rownames(de_results)

n_overlap <- length(intersect(msigdb_genes, de_genes))
message("Gene overlap: ", n_overlap, " / ", length(de_genes),
        " (", round(100 * n_overlap / length(de_genes), 1), "%)")

# Should be >80% for good analysis
```
