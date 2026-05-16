# Build cleaned corpora + DFMs for presidential discourses and Reddit.

library(tidyverse)
library(pdftools)
library(stringi)
library(quanteda)

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

# --- Discourses ----------------------------------------------------------------
discursos <- list.files("data/raw/discursos", "\\.pdf$", full.names = TRUE) |>
  map_dfr(\(f) tibble(doc_id = tools::file_path_sans_ext(basename(f)),
                      text   = pdf_text(f))) |>
  mutate(text = str_split(text, "\n{2,}")) |> unnest(text) |>
  mutate(text = str_squish(str_replace_all(text, "\n", " "))) |>
  filter(text != "", !str_detect(text, "-{5,}|^[0-9]+$"),
         !text %in% c("Asambleístas,", "PRESENTAR INVITADOS")) |>
  mutate(text = stri_trans_general(text, "Latin-ASCII"),
         paragraph_id = row_number())

saveRDS(discursos, "data/processed/discursos_paragraphs.rds")

discursos_stop <- c("republica", "dominicana", "dominicano", "dominicanos",
                    "presidente", "gobierno", "pais", "nacional", "nacion",
                    "ano", "anos", "hoy", "asi", "ser", "hacer", "solo",
                    "tambien", "mas", "si", "tan", "vamos", "hemos")

corpus_d <- corpus(discursos, text_field = "text", docid_field = "paragraph_id")
dfm_d <- tokens(corpus_d, remove_punct = TRUE, remove_symbols = TRUE,
                remove_numbers = TRUE, remove_url = TRUE) |>
  tokens_tolower() |>
  tokens_remove(c(stopwords("es"), discursos_stop)) |>
  dfm() |> dfm_trim(min_termfreq = 5, min_docfreq = 2)

saveRDS(corpus_d, "data/processed/discursos_corpus.rds")
saveRDS(dfm_d,    "data/processed/discursos_dfm.rds")

# --- Reddit --------------------------------------------------------------------
reddit <- read_csv("data/raw/dataset_reddit.csv", show_col_types = FALSE) |>
  mutate(text = if_else(dataType == "post",
                        paste(replace_na(title, ""), replace_na(body, "")),
                        body) |> str_squish(),
         upVotes = as.integer(upVotes)) |>
  filter(!is.na(text), nchar(text) >= 20, username != "AutoModerator") |>
  mutate(text = str_remove_all(text, "https?://\\S+|Images:") |> str_squish(),
         text = stri_trans_general(text, "Latin-ASCII"),
         post_id = row_number())

saveRDS(reddit, "data/processed/reddit_cleaned.rds")

reddit_stop <- c("republica", "dominicana", "dominicano", "dominicanos",
                 "ano", "anos", "hoy", "asi", "vez", "ahi", "ahora", "gente",
                 "mucho", "solo", "tambien", "tan", "todo", "deleted",
                 "removed", "amp", "x200b")

corpus_r <- corpus(reddit, text_field = "text", docid_field = "post_id")
dfm_r <- tokens(corpus_r, remove_punct = TRUE, remove_symbols = TRUE,
                remove_numbers = TRUE, remove_url = TRUE) |>
  tokens_tolower() |>
  tokens_remove(c(stopwords("es"), reddit_stop)) |>
  tokens_keep(min_nchar = 3) |>
  dfm() |> dfm_trim(min_termfreq = 5, min_docfreq = 2)

saveRDS(corpus_r, "data/processed/reddit_corpus.rds")
saveRDS(dfm_r,    "data/processed/reddit_dfm.rds")

message("Discursos: ", nrow(discursos), " paragraphs. Reddit: ", nrow(reddit), " docs.")
