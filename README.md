# The Dialectic of Dominican Identity in Migration

Replication materials for an NLP-based exploration of how Haitian migration
is framed in Dominican Republic presidential discourse and in Dominican
Reddit conversations, combined with descriptive statistics on migration,
arrests, naturalizations, and border detentions.

Course: DOPP 5688 — Text as Data (Spring 2026), CEU.
Author: Daniel Navarro (`navarro_daniel@student.ceu.edu`).

## Pipeline

Scripts run top-to-bottom. Each script writes its outputs to disk so the
next stage can pick them up without re-running the prior one.

| Script | Inputs | Outputs |
|---|---|---|
| `01_data_collection.R` | https://presidencia.gob.do/discursos | `data/raw/discursos/*.pdf` |
| `02_preprocessing.R` | `data/raw/discursos/*.pdf`, `data/raw/dataset_reddit.csv` | `data/processed/discursos_corpus.rds`, `data/processed/reddit_corpus.rds`, `data/processed/*_dfm.rds` |
| `03_RD_descriptive_stats.R` | `data/raw/{arrestos,detenidos_frontera,Naturalizaciones}.csv` | `output/figures/descriptive_stats/*.png` |
| `04_NLP.R` | `data/processed/*` | `output/figures/nlp/*.png`, `output/tables/*` |

The PDFs are already committed to `data/raw/discursos/`. If you want to
re-scrape them from scratch, run `01_data_collection.R`. Both reddit and
migration CSVs are committed as well — they're small and hard to
re-collect.

## Folder layout

```
.
├── 01_data_collection.R
├── 02_preprocessing.R
├── 03_RD_descriptive_stats.R
├── 04_NLP.R
├── data/
│   ├── raw/                      # PDFs + CSVs as collected
│   └── processed/                # corpora, DFMs (built by 02)
├── output/
│   ├── figures/
│   │   ├── descriptive_stats/    # plots used in the EDA section
│   │   └── nlp/                  # wordclouds, topics, sentiment
│   └── tables/
└── dialectical_identity_in_RD.Rproj
```

## Setup

Open the `.Rproj` in RStudio (this sets the working directory) and install
the dependencies:

```r
install.packages(c(
  "tidyverse", "rvest", "pdftools", "stringi",
  "quanteda", "quanteda.textstats", "quanteda.textplots",
  "seededlda", "topicmodels", "ldatuning",
  "syuzhet", "ggrepel", "scales"
))
```

All analysis is performed on Spanish text. The scripts and comments are in
English.

## Notes on the data

- Presidential discourses come from the official Presidencia
  (`presidencia.gob.do`) — public domain.
- Reddit data is scraped from `r/Dominicanos`. The `AutoModerator` user is
  filtered out during preprocessing.
- Migration CSVs (`arrestos`, `detenidos_frontera`, `Naturalizaciones`) are
  reused from the original 2023 migration report. They are Latin-1 encoded
  with the column `AÑO` mojibaked; the preprocessing script handles this.
