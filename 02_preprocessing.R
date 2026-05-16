# ==============================================================================
# 02_preprocessing.R
#
# Build two cleaned corpora plus their DFMs:
#   1. Presidential discourses, extracted from data/raw/discursos/*.pdf
#   2. Reddit posts/comments from r/Dominicanos
#
# Both corpora are Spanish. We keep two granularities: paragraph-level
# (closer to the natural unit of analysis for sentiment & keyword work) and
# document-level (longer bags of words for LDA scaling).
#
# Output files (under data/processed/):
#   - discursos_paragraphs.rds       tibble, one row per paragraph
#   - discursos_corpus.rds           quanteda corpus, paragraph granularity
#   - discursos_dfm.rds              DFM, cleaned + Spanish stopwords removed
#   - reddit_cleaned.rds             tibble, one row per post/comment
#   - reddit_corpus.rds              quanteda corpus
#   - reddit_dfm.rds                 DFM, cleaned + Spanish stopwords removed
# ==============================================================================

library(tidyverse)
library(pdftools)
library(stringi)
library(quanteda)

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)


# ==============================================================================
# PART A — Presidential discourses
# ==============================================================================

pdf_files <- list.files("data/raw/discursos",
                        pattern = "\\.pdf$", full.names = TRUE)

# --- Extract paragraphs from a single PDF ------------------------------------
# Strategy: split each page on blank lines (2+ newlines), collapse internal
# line wraps inside a paragraph, drop boilerplate (page numbers, divider
# lines, ceremonial stock phrases the president repeats verbatim).

process_pdf <- function(file_path) {
  pdf_text(file_path) |>
    enframe(name = "page", value = "text") |>
    mutate(text = str_split(text, "\n{2,}")) |>
    unnest(text) |>
    mutate(
      text = str_replace_all(text, "\n", " "),
      text = str_squish(text)
    ) |>
    filter(
      text != "",
      !str_detect(text, "-{5,}"),         # divider rules
      !str_detect(text, "^[0-9]+$"),      # standalone page numbers
      text != "Asambleístas,",
      text != "PRESENTAR INVITADOS"       # stage direction in some scripts
    ) |>
    mutate(
      doc_id = tools::file_path_sans_ext(basename(file_path))
    ) |>
    relocate(doc_id, page)
}

df_discursos <- map_dfr(pdf_files, process_pdf) |>
  # Strip accents so downstream tokenization is robust to inconsistent
  # encoding across PDFs. We keep Spanish — only the diacritics are removed.
  mutate(text = stri_trans_general(text, "Latin-ASCII")) |>
  mutate(paragraph_id = row_number())

message("Discursos: ", nrow(df_discursos), " paragraphs from ",
        n_distinct(df_discursos$doc_id), " PDFs")

saveRDS(df_discursos, "data/processed/discursos_paragraphs.rds")


# --- Build the quanteda corpus + DFM -----------------------------------------
corpus_discursos <- corpus(df_discursos,
                           text_field  = "text",
                           docid_field = "paragraph_id")

# Extra noise specific to Dominican political discourse. Without this list the
# topic-model output is dominated by ceremonial / functional language that
# appears in every speech.
discursos_extra_stop <- c(
  "republica", "dominicana", "republica_dominicana", "dominicano", "dominicanos",
  "presidente", "gobierno", "pais", "nacional", "nacion",
  "ano", "anos", "hoy", "asi", "ser", "hacer", "solo", "tambien",
  "mas", "si", "ademas", "cada", "tan",
  "vamos", "haremos", "hemos", "estamos", "tenemos", "queremos"
)

toks_discursos <- tokens(
    corpus_discursos,
    remove_punct   = TRUE,
    remove_symbols = TRUE,
    remove_numbers = TRUE,
    remove_url     = TRUE
  ) |>
  tokens_tolower() |>
  tokens_remove(stopwords("es")) |>
  tokens_remove(discursos_extra_stop)

# Compound a few Dominican-political multi-word phrases that lose meaning when
# split. Discovered via textstat_collocations() in earlier exploration.
toks_discursos <- tokens_compound(
  toks_discursos,
  pattern = phrase(c(
    "republica dominicana", "santo domingo", "primera vez",
    "no hay", "rd millones"
  ))
)

dfm_discursos <- dfm(toks_discursos) |>
  dfm_trim(min_termfreq = 5, min_docfreq = 2)

saveRDS(corpus_discursos, "data/processed/discursos_corpus.rds")
saveRDS(dfm_discursos,    "data/processed/discursos_dfm.rds")


# ==============================================================================
# PART B — Reddit (r/Dominicanos)
# ==============================================================================

reddit_raw <- read_csv("data/raw/dataset_reddit.csv",
                       show_col_types = FALSE)

# Posts have content in `title` (and optionally `body`); comments have only
# `body`. Concatenate so each row has one canonical `text` field. Filter
# AutoModerator (boilerplate) and very short stubs that carry no semantic
# content.
reddit <- reddit_raw |>
  mutate(
    text = case_when(
      dataType == "post"    ~ paste(title %||% "", body %||% ""),
      dataType == "comment" ~ body,
      TRUE                  ~ NA_character_
    ),
    text = str_squish(text),
    upVotes = as.integer(upVotes)
  ) |>
  filter(
    !is.na(text),
    nchar(text) >= 20,
    username != "AutoModerator"
  ) |>
  mutate(
    # Strip image-preview noise that Reddit scrapers often leave in.
    text = str_remove_all(text, "https?://\\S+"),
    text = str_remove_all(text, "Images:"),
    text = str_squish(text),
    text = stri_trans_general(text, "Latin-ASCII"),
    post_id = row_number()
  )

message("Reddit: ", nrow(reddit), " posts/comments after cleaning")

saveRDS(reddit, "data/processed/reddit_cleaned.rds")


# --- Build the quanteda corpus + DFM -----------------------------------------
corpus_reddit <- corpus(reddit, text_field = "text", docid_field = "post_id")

# Reddit-specific noise: domain words from the subreddit, generic agreement
# tokens, common emoji-adjacent tokens.
reddit_extra_stop <- c(
  "republica", "dominicana", "dominicano", "dominicanos",
  "ano", "anos", "hoy", "asi", "ser", "hacer", "solo", "tambien",
  "mas", "si", "no", "que", "como", "pues", "vez", "ahi", "ahora",
  "gente", "mucho", "muchos", "decir", "dice", "estar", "tener",
  "porque", "tambien", "siempre", "nunca", "tan", "todo", "toda",
  "deleted", "removed", "https", "http", "www", "com",
  "amp", "x200b"
)

toks_reddit <- tokens(
    corpus_reddit,
    remove_punct   = TRUE,
    remove_symbols = TRUE,
    remove_numbers = TRUE,
    remove_url     = TRUE
  ) |>
  tokens_tolower() |>
  tokens_remove(stopwords("es")) |>
  tokens_remove(reddit_extra_stop) |>
  tokens_keep(min_nchar = 3)

dfm_reddit <- dfm(toks_reddit) |>
  dfm_trim(min_termfreq = 5, min_docfreq = 2)

saveRDS(corpus_reddit, "data/processed/reddit_corpus.rds")
saveRDS(dfm_reddit,    "data/processed/reddit_dfm.rds")


message("Preprocessing complete. Artifacts in data/processed/.")
