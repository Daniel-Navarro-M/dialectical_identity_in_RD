# The Dialectic of Dominican Identity in Migration

Replication materials for an NLP-based exploration of how Haitian migration
is framed in Dominican Republic presidential discourse and in Dominican
Reddit conversations, combined with descriptive statistics on migration,
arrests, naturalizations, and border detentions.

Course: DOPP 5688 — Text as Data (Spring 2026), CEU.
Author: Daniel Navarro (`navarro_daniel@student.ceu.edu`).

## Pipeline

Reddit input (`data/raw/dataset_reddit_translated.csv`) was produced once
by an out-of-band Helsinki MarianMT (`Helsinki-NLP/opus-mt-en-es`) pass on
the original `dataset_reddit.csv`. The translated CSV is committed; the
R pipeline reads it directly and drops the few rows where translation
failed (they stay flagged `lang == "en"` and `translated == FALSE`).

R pipeline (run top to bottom):

| Script | Inputs | Outputs |
|---|---|---|
| `01_data_collection.R` | https://presidencia.gob.do/discursos | `data/raw/discursos/*.pdf` |
| `02_preprocessing.R` | `data/raw/discursos/*.pdf`, `data/raw/dataset_reddit_translated.csv` | `data/processed/{discursos,reddit}_{corpus,dfm}.rds`, `data/processed/reddit_sentences.rds` |
| `03_RD_descriptive_stats.R` | `data/raw/{arrestos,detenidos_frontera,Naturalizaciones}.csv` | `output/figures/descriptive_stats/*.png` |
| `04_NLP_topics.R` | `data/processed/*` | keyword tables, KWIC, ldatuning K-sweep, seeded LDA (Reddit) |
| `05_NLP_sentiment.R` | `data/processed/*` | transformer sentiment (uses reticulate), negativity, H1 plot |

Scripts are designed to be run interactively, section by section. Key
decision points (DFM trimming thresholds in `02`, K per corpus in `04`) are
exposed at the top of their section so they can be revisited after
exploration.

## Folder layout

```
.
├── 01_data_collection.R
├── 02_preprocessing.R
├── 03_RD_descriptive_stats.R
├── 04_NLP_topics.R
├── 05_NLP_sentiment.R
├── data/
│   ├── raw/                      # PDFs + CSVs
│   └── processed/                # corpora, DFMs, sentence-level table
├── output/
│   ├── figures/
│   │   ├── descriptive_stats/
│   │   └── nlp/
│   └── tables/
└── dialectical_identity_in_RD.Rproj
```

## Setup

Open the `.Rproj` and install the R dependencies:

```r
install.packages(c(
  "tidyverse", "rvest", "pdftools", "stringi",
  "quanteda", "quanteda.textstats", "quanteda.textplots",
  "seededlda", "topicmodels", "ldatuning",
  "tidytext", "scales", "broom", "reticulate"
))
```

Sentiment in `05_NLP_sentiment.R` uses a Spanish transformer
(`pysentimiento/robertuito-sentiment-analysis`) called via reticulate +
HuggingFace `transformers`, following the same pattern as the Day 5 UK
manifestos prep script. Python side:

```bash
pip install transformers torch
```

If you run inside a conda environment, uncomment the `use_condaenv(...)`
line at the top of `05_NLP_sentiment.R`.

## Notes on the data

- Presidential discourses come from Presidencia (`presidencia.gob.do`).
- Reddit data is scraped from `r/Dominicanos` and pre-filtered to posts
  and comments containing at least one of `haiti`, `haitianos`,
  `extranjeros`, `inmigrantes`, `inmigracion`, `migracion`.
  `AutoModerator` is filtered out during preprocessing.
- Migration CSVs (`arrestos`, `detenidos_frontera`, `Naturalizaciones`)
  are reused from the 2023 migration report. Two of them are Latin-1
  encoded — `03_RD_descriptive_stats.R` handles this with
  `fileEncoding = "Latin1"`.
