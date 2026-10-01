# Master Tables

> **Superseded.** GSEA and master tables run through the installed `bulkiRNA` package; see skill `bulkirna` and `bulk-rnaseq-gsea`.

**Module:** `master_tables.md`
**Purpose:** Schema standardization, CSV contracts, and R/Python bridging

---

## 1. The Master Tables Pattern

### 1.1 Purpose

Master tables serve as the **contract between R and Python**:

```
R Analysis Layer                Python Visualization Layer
┌─────────────────┐            ┌─────────────────────────┐
│ gseaResult      │            │                         │
│ limma fit       │  ──CSV──>  │ pandas DataFrame        │
│ DGEList         │            │ plotly/matplotlib       │
│ Complex objects │            │ Simple data structures  │
└─────────────────┘            └─────────────────────────┘
```

**Benefits:**
- Python doesn't need to read RDS files
- Schema is explicit and documented
- Easy to share with collaborators
- Language-agnostic downstream analysis

### 1.2 Core Principle

**R computes → Master tables normalize → Python visualizes**

---

## 2. Standard Master Tables

### 2.1 GSEA Master Table

**File:** `master_gsea_table.csv`

| Column | Type | Description |
|--------|------|-------------|
| `pathway_id` | string | Original pathway identifier |
| `pathway_name` | string | Cleaned pathway name |
| `database` | string | Source database (Hallmark, KEGG, etc.) |
| `nes` | float | Normalized Enrichment Score |
| `pvalue` | float | Nominal p-value |
| `padj` | float | FDR-adjusted p-value |
| `set_size` | int | Number of genes in pathway |
| `core_enrichment` | string | Leading edge genes (comma-separated) |
| `contrast` | string | DE contrast name |
| `direction` | string | "Up" or "Down" |

### 2.2 DE Master Table

**File:** `master_de_table.csv`

| Column | Type | Description |
|--------|------|-------------|
| `gene_symbol` | string | Gene symbol (primary key) |
| `ensembl_id` | string | Ensembl ID |
| `logFC` | float | Log2 fold change |
| `AveExpr` | float | Average expression |
| `t` | float | t-statistic |
| `P.Value` | float | Raw p-value |
| `adj.P.Val` | float | FDR-adjusted p-value |
| `contrast` | string | Contrast name |
| `significant` | bool | adj.P.Val < FDR cutoff |
| `direction` | string | "Up", "Down", or "NS" |

### 2.3 TF Activities Table

**File:** `master_tf_activities.csv`

| Column | Type | Description |
|--------|------|-------------|
| `tf` | string | Transcription factor name |
| `source` | string | Regulon source (dorothea, collectri) |
| `activity` | float | Inferred activity score |
| `p_value` | float | Statistical significance |
| `contrast` | string | Contrast name |
| `confidence` | string | Regulon confidence level (A-E) |

### 2.4 Pathway Activities Table

**File:** `master_progeny_activities.csv`

| Column | Type | Description |
|--------|------|-------------|
| `pathway` | string | PROGENy pathway name |
| `activity` | float | Pathway activity score |
| `p_value` | float | Statistical significance |
| `contrast` | string | Contrast name |

---

## 3. Schema Normalization

### 3.1 GSEA Normalization Function

```r
normalize_gsea_results <- function(gsea_obj, database, contrast) {
  # Handle both clusterProfiler and fgsea outputs
  if (inherits(gsea_obj, "gseaResult")) {
    # clusterProfiler output
    df <- gsea_obj@result
    tibble(
      pathway_id = df$ID,
      pathway_name = clean_pathway_name(df$Description),
      database = database,
      nes = df$NES,
      pvalue = df$pvalue,
      padj = df$p.adjust,
      set_size = df$setSize,
      core_enrichment = df$core_enrichment,
      contrast = contrast,
      direction = ifelse(df$NES > 0, "Up", "Down")
    )
  } else if (is.data.frame(gsea_obj)) {
    # fgsea output
    tibble(
      pathway_id = gsea_obj$pathway,
      pathway_name = clean_pathway_name(gsea_obj$pathway),
      database = database,
      nes = gsea_obj$NES,
      pvalue = gsea_obj$pval,
      padj = gsea_obj$padj,
      set_size = gsea_obj$size,
      core_enrichment = sapply(gsea_obj$leadingEdge, paste, collapse = ","),
      contrast = contrast,
      direction = ifelse(gsea_obj$NES > 0, "Up", "Down")
    )
  }
}
```

### 3.2 Pathway Name Cleaning

```r
clean_pathway_name <- function(pathway_names) {
  pathway_names %>%
    str_replace_all("^HALLMARK_", "") %>%
    str_replace_all("^KEGG_", "") %>%
    str_replace_all("^REACTOME_", "") %>%
    str_replace_all("^GO_", "") %>%
    str_replace_all("^WP_", "") %>%
    str_replace_all("_", " ") %>%
    str_to_title() %>%
    str_trim()
}
```

### 3.3 DE Normalization Function

```r
normalize_de_results <- function(de_table, contrast, fdr_cutoff = 0.05) {
  de_table %>%
    as_tibble(rownames = "gene_symbol") %>%
    mutate(
      contrast = contrast,
      significant = adj.P.Val < fdr_cutoff,
      direction = case_when(
        !significant ~ "NS",
        logFC > 0 ~ "Up",
        logFC < 0 ~ "Down"
      )
    ) %>%
    select(
      gene_symbol,
      ensembl_id = any_of("ensembl_id"),
      logFC,
      AveExpr,
      t,
      P.Value,
      adj.P.Val,
      contrast,
      significant,
      direction
    )
}
```

---

## 4. Creating Master Tables

### 4.1 GSEA Master Table

```r
# Combine all GSEA results
create_gsea_master_table <- function(all_gsea_results, contrast_name) {
  # all_gsea_results is a named list: list(Hallmark = ..., KEGG = ..., ...)

  master_table <- bind_rows(
    lapply(names(all_gsea_results), function(db_name) {
      normalize_gsea_results(
        gsea_obj = all_gsea_results[[db_name]],
        database = db_name,
        contrast = contrast_name
      )
    })
  )

  # Sort by significance
  master_table <- master_table %>%
    arrange(padj, desc(abs(nes)))

  # Save
  write_csv(master_table, file.path(DIR_TABLES, "master_gsea_table.csv"))
  message("Saved master_gsea_table.csv: ", nrow(master_table), " pathways")

  return(master_table)
}
```

### 4.2 DE Master Table

```r
create_de_master_table <- function(de_results, contrast_name, fdr_cutoff = 0.05) {
  master_table <- normalize_de_results(de_results, contrast_name, fdr_cutoff)

  write_csv(master_table, file.path(DIR_TABLES, "master_de_table.csv"))
  message("Saved master_de_table.csv: ", nrow(master_table), " genes")

  return(master_table)
}
```

---

## 5. Schema Validation

### 5.1 R Validation

```r
validate_gsea_schema <- function(df) {
  required_cols <- c("pathway_id", "pathway_name", "database", "nes",
                     "pvalue", "padj", "set_size", "core_enrichment",
                     "contrast", "direction")

  missing <- setdiff(required_cols, names(df))

  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # Type checks
  stopifnot(is.character(df$pathway_id))
  stopifnot(is.numeric(df$nes))
  stopifnot(is.numeric(df$padj))

  message("Schema validation passed: ", nrow(df), " rows")
  invisible(TRUE)
}
```

### 5.2 Python Validation

```python
def validate_schema(df, table_name, schemas):
    """Validate DataFrame against expected schema."""
    schema = schemas.get(table_name)
    if not schema:
        raise ValueError(f"Unknown table: {table_name}")

    required = schema['required_columns']
    missing = set(required) - set(df.columns)

    if missing:
        raise ValueError(f"Missing columns in {table_name}: {missing}")

    print(f"Schema validation passed: {len(df)} rows")
    return True

# Schema definitions
SCHEMAS = {
    'master_gsea_table': {
        'required_columns': [
            'pathway_id', 'pathway_name', 'database', 'nes',
            'pvalue', 'padj', 'set_size', 'core_enrichment',
            'contrast', 'direction'
        ]
    },
    'master_de_table': {
        'required_columns': [
            'gene_symbol', 'logFC', 'P.Value', 'adj.P.Val',
            'contrast', 'significant', 'direction'
        ]
    }
}
```

---

## 6. Reading Master Tables

### 6.1 In R

```r
# Load for visualization
gsea_data <- read_csv(file.path(DIR_TABLES, "master_gsea_table.csv"))
de_data <- read_csv(file.path(DIR_TABLES, "master_de_table.csv"))

# Filter for plotting
sig_pathways <- gsea_data %>%
  filter(padj < 0.05) %>%
  slice_max(abs(nes), n = 20)
```

### 6.2 In Python

```python
from pathlib import Path
import pandas as pd

# Load master tables
tables_dir = Path("03_results/tables")
gsea_data = pd.read_csv(tables_dir / "master_gsea_table.csv")
de_data = pd.read_csv(tables_dir / "master_de_table.csv")

# Filter for plotting
sig_pathways = (gsea_data
    .query("padj < 0.05")
    .nlargest(20, "nes", key=abs))
```

---

## 7. Best Practices

### 7.1 Column Naming

- Use `snake_case` for all column names
- Be explicit: `adj.P.Val` not `fdr`
- Include units in name if needed: `logFC` (log2)

### 7.2 Data Types

- Store gene lists as comma-separated strings
- Use float for all numeric values
- Use string for categorical/factor columns
- Avoid storing R-specific objects

### 7.3 File Naming

```
master_{type}.csv           # Combined across databases/contrasts
master_{type}_{subset}.csv  # If subset needed

Examples:
master_gsea_table.csv       # All GSEA results
master_de_table.csv         # All DE results
master_tf_activities.csv    # TF results
```

### 7.4 Documentation

Always include a README in `03_results/tables/`:

```markdown
# Master Tables

Generated: YYYY-MM-DD

## Files

- `master_gsea_table.csv`: GSEA results across all databases
- `master_de_table.csv`: Differential expression results

## Schema

See scio/docs/guidelines/master_tables.md

## Regeneration

```bash
Rscript 02_analysis/1.5.create_master_tables.R
```
```
