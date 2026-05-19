# Build sentence-level corpora, and DFMs, and for both
# presidential discourses and r/Dominicanos. Sentence is the unit of analysis
# because (i) transformer sentiment models expect short, single-sentiment text,
# (ii) the migration vs. non-migration comparison in H1 requires within-post
# variation, which sentence-level scoring preserves, and (iii) the
# pre-trained transformer model was trained on tweet-length inputs

rm(list = ls())

library(tidyverse)
library(pdftools)
library(stringi)
library(quanteda)
library(quanteda.textstats)
library(cld3)

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

## Parameters ----

# DFM trimming. Drops tokens that appear fewer than MIN_TERMFREQ times overall
# or in fewer than MIN_DOCFREQ sentences. The whitelist below rescues
# vocabulary so trimming does not delete the selected words that
# are related to the research topic (migration and racially related terms).
MIN_TERMFREQ <- 5
MIN_DOCFREQ  <- 2

# Whitelist:
# Based on the seeded-LDA anchor dictionaries, race related terms
# and rhetorically loaded terms related to migration issues and
# negative terms flagged during EDA that appeared along hait*

whitelist_globs <- c(
  "haiti*", "haitian*", "migra*", "inmigra*", "migrant*", "inmigrant*",
  "fronter*", "muro", "deport*", "repatri*", "refugi*", "indocumenta*",
  "extranjer*", "binacional", "isla",
  "raza", "racis*", "racial*", "negro*", "moreno*", "blanco*",
  "etnic*", "discrimina*", "perfila*",
  "invad*", "salvaje*", "cobarde*", "ilegal*", "violar",
  "armad*", "frenar", "salvar", "desplegar",
  "cadena", "perpetua", "documentado"
)

# Custom Spanish stoplists. The default quanteda::stopwords("es")
# misses two layers of corpus-specific noise
#
# For discourses the structural boilerplate is the ceremonial scaffolding
# that is removed here

discursos_stop <- c("cada", "ademas", "san", "puerto_plata",
  "declaraciones", "abinader", "republica", "dominicana", "dominicano",
  "dominicanos", "presidente", "gobierno", "pais", "nacional", "nacion",
  "ano", "anos", "hoy", "asi", "ser", "hacer", "solo", "tambien",
  "mas", "si", "tan", "vamos", "hemos", "primera", "vez", "muchas", "gracias"
)

# For Reddit the structural noise is platform-specific (deleted/removed
# placeholders, x200b zero-width space, http/www fragments left over from URL
# stripping) plus high-frequency filler vocabulary that surfaced when
# inspecting topfeatures. I also removed Dominican geography names 
# as they appeared around hait*-containing sentences but carry no topical signal.

reddit_stop <- c("decir", "van", "dia", "entonces", 
  "republica", "dominicana", "dominicano", "dominicanos",
  "deleted", "removed", "amp", "x200b", "http", "https", "www",
  "ano", "anos", "hoy", "asi", "vez", "ahi", "ahora", "gente",
  "mucho", "solo", "tambien", "tan", "todo", "mas", "aqui", "estan",
  "ser", "cosas", "siempre", "puedes", "cada", "tener", "puede",
  "hace", "hacer", "mismo", "dijo", "alguien", "despues", "alla",
  "dos", "segun", "creo", "ver",
  "libano", "san", "santo", "domingo", "puerto", "ciudad",
  "juan", "francisco", "parte", "aunque", "pedro", "macoris", "muchas", "veces",
  "jose", "ocoa", "diario_libre", "punta_cana"
)

compound_phrases <- phrase(c("cadena perpetua", "millones pesos",
                             "pena muerte", "redes sociales", "derechos humanos",
                             "politica migratoria", "calidad vida", "puerto plata",
                             "comunidad internacional", "clase media", "diario libre",
                             "punta cana"
                             ))

# Spanish sentence splitter: punctuation followed by whitespace + capital and accents.
split_sent <- \(t) stri_split_regex(t, "(?<=[.!?])\\s+(?=[A-ZÁÉÍÓÚÑ])")

# Tokenization + DFM builder ----

build_corpus_dfm <- function(df, stops, min_nchar = 3) {
  corp <- corpus(df, text_field = "text", docid_field = "sentence_index")
  toks <- tokens(corp, remove_punct = TRUE, remove_symbols = TRUE,
                 remove_numbers = TRUE, remove_url = TRUE) |>
    tokens_tolower() |>
    tokens_compound(pattern = compound_phrases) |>
    tokens_remove(c(stopwords("es"), stops)) |>
    tokens_keep(min_nchar = min_nchar)
  dfm_full <- dfm(toks)
  keep <- union(
    featnames(dfm_trim(dfm_full, min_termfreq = MIN_TERMFREQ,
                       min_docfreq = MIN_DOCFREQ)),
    featnames(dfm_select(dfm_full, pattern = whitelist_globs, valuetype = "glob"))
  )
  list(corpus  = corp,
       toks    = toks,
       dfm_full = dfm_full,
       dfm     = dfm_select(dfm_full, pattern = keep,
                            selection = "keep", valuetype = "fixed"))
}

# --- Discourses ----

# date join for discourses.
discursos_meta <- read_csv("data/raw/discursos_index.csv", show_col_types = FALSE) |>
    select(doc_id = id, title = discourse, date = datetime)

# converting the discourses into sentences. Sentences are better for the transformer

discursos_sentences <- list.files("data/raw/discursos", "\\.pdf$",
                                  full.names = TRUE) |>
  map_dfr(\(f) tibble(doc_id = tools::file_path_sans_ext(basename(f)),
                      text   = pdf_text(f))) |>
  mutate(text = str_split(text, "\n{2,}")) |> unnest(text) |>
  mutate(text = str_squish(str_replace_all(text, "\n", " "))) |>
  filter(text != "",
         !str_detect(text, "-{5,}|^[0-9]+$"),
         !text %in% c("Asambleístas,", "PRESENTAR INVITADOS")) |>
  mutate(text = stri_trans_general(text, "Latin-ASCII")) |>
  mutate(sent = split_sent(text)) |> unnest(sent) |>
  mutate(sent = str_squish(sent)) |>
  filter(nchar(sent) > 20, nchar(sent) < 800) |>
  left_join(discursos_meta, by = "doc_id") |>
  arrange(date, doc_id) |>
  group_by(doc_id) |>
  mutate(sentence_within_doc = row_number()) |>
  ungroup() |>
  mutate(sentence_index = row_number()) |>
  transmute(corpus = "Discourses", sentence_index, sentence_within_doc,
            doc_id, title, date, text = sent)

D <- build_corpus_dfm(discursos_sentences, discursos_stop)

saveRDS(discursos_sentences, "data/processed/discursos_sentences.rds")
saveRDS(D$corpus, "data/processed/discursos_corpus.rds")
saveRDS(D$dfm, "data/processed/discursos_dfm.rds")

# --- Reddit ----

# Posts and comments are concatenated into a single text field (post: title +
# body; comment: body). AutoModerator is filtered because its a bot that always
# says the same. cld3 language detection drops English- rows
# Length filter (>20 and <800 characters) removes fragments and
# merged-paragraph artifacts. FIltered a user's posts that were historical articles
reddit_sentences <- read_csv("data/raw/dataset_reddit.csv",
                             show_col_types = FALSE) |>
  mutate(text = if_else(dataType == "post",
                        paste(replace_na(title, ""), replace_na(body, "")),
                        body) |> str_squish(),
         upVotes = as.integer(upVotes)) |>
  filter(!is.na(text), nchar(text) >= 20, username != "AutoModerator") |>
  filter(username != "Dominicanos-ModTeam") |>
  filter(username != "arturo14") |> 
  filter(!(username == "DRmetalhead19" & dataType == "post")) |> 
  mutate(text = str_remove_all(text, "https?://\\S+|Images:") |> str_squish(),
         lang = cld3::detect_language(text)) |>
  filter(lang == "es") |>
  mutate(text = stri_trans_general(text, "Latin-ASCII"),
         post_id = row_number()) |>
  mutate(sent = split_sent(text)) |> unnest(sent) |>
  mutate(sent = str_squish(sent)) |>
  filter(nchar(sent) > 20, nchar(sent) < 800) |>
  arrange(post_id) |>
  group_by(post_id) |>
  mutate(sentence_within_doc = row_number()) |>
  ungroup() |>
  mutate(sentence_index = row_number()) |>
  transmute(corpus = "Reddit", sentence_index, sentence_within_doc,
            doc_id = as.character(post_id), post_id,
            dataType, username, upVotes, text = sent)

R <- build_corpus_dfm(reddit_sentences, reddit_stop)

saveRDS(reddit_sentences, "data/processed/reddit_sentences.rds")
saveRDS(R$corpus, "data/processed/reddit_corpus.rds")
saveRDS(R$dfm, "data/processed/reddit_dfm.rds")

# --- Pre-model EDA ----

cat("Discourses sentences: ", nrow(discursos_sentences),
    " | DFM features:", nfeat(D$dfm), "\n")
cat("Reddit sentences:", nrow(reddit_sentences),
    " | DFM features:", nfeat(R$dfm), "\n")

## TOP 25 FEATURES PER CORPUS ----
cat("\n-- Discourses --\n"); print(topfeatures(D$dfm, 25))
cat("\n-- Reddit --\n");     print(topfeatures(R$dfm, 25))

## COLLOCATIONS ----
cat("\n-- Discourses --\n")
print(head(textstat_collocations(D$toks, size = 2, min_count = 10), 15))
cat("\n-- Reddit --\n")
print(head(textstat_collocations(R$toks, size = 2, min_count = 10), 15))

# KWIC
cat("\n-- Discourses --\n"); print(head(kwic(tokens(D$corpus), "hait*", 6), 20))
cat("\n-- Reddit --\n");     print(head(kwic(tokens(R$corpus), "hait*", 6), 20))

cat("\n-- Discourses --\n"); print(head(kwic(tokens(D$corpus), "migra*", 6), 20))
cat("\n-- Reddit --\n");     print(head(kwic(tokens(R$corpus), "migra*", 6), 20))

## Keyword survival check ---- 
# verifiyng that the migration / racialization vocabulary
# of interest is still in the trimmed DFM after the whitelist union. Anything
# that surfaces here as NA is either absent from the corpus or lost to
# trimming; whitelist entries should never be NA.
mig_check <- c("haitiano","haitianos","haiti","migracion","migrante","migrantes",
               "frontera","fronterizo","deportacion","muro","extranjero",
               "extranjeros","inmigrante","inmigrantes","raza","negro","negros",
               "moreno","morenos","ilegal","indocumentado","discriminacion",
               "racismo","invadir","salvaje","cobarde","armado")
print(tibble(word = mig_check,
             tf_d = featfreq(D$dfm_full)[mig_check],
             tf_r = featfreq(R$dfm_full)[mig_check]))

## Term-frequency exploration ----
# vocabulary size at candidate trimming thresholds,
# and the log-frequency distribution. Used to decide MIN_TERMFREQ.
print(sapply(c(1, 2, 3, 5, 10, 20),
             \(k) c(discursos = sum(featfreq(D$dfm_full) >= k),
                    reddit    = sum(featfreq(R$dfm_full) >= k))))

par(mfrow = c(1, 2))
hist(log10(featfreq(D$dfm_full)), breaks = 50,
     main = "log10 term freq — discourses", xlab = "log10(freq)")
hist(log10(featfreq(R$dfm_full)), breaks = 50,
     main = "log10 term freq — reddit",     xlab = "log10(freq)")
par(mfrow = c(1, 1))