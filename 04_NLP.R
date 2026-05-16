# ==============================================================================
# 04_NLP.R
#
# NLP analysis of presidential discourses + r/Dominicanos posts/comments.
# Both corpora are in Spanish; all script + comments are in English.
#
# What this script does, in order:
#   1. Build sentence-level corpora for both sources.
#   2. Explore keyword frequencies around migration terms (hait*, migra*, …)
#      and inspect representative sentences (KWIC).
#   3. Compare wordcloud / top-feature plots across the two corpora.
#   4. Choose a number of topics via ldatuning metrics, then fit a seeded
#      LDA (k = 6, following Griffiths 2004) on each source separately.
#   5. Compute sentiment + a continuous negativity score per document using
#      the NRC Spanish lexicon. Reddit results are also weighted by upvotes.
#
# Inputs:  data/processed/{discursos,reddit}_{corpus,dfm,cleaned,paragraphs}.rds
# Outputs: output/figures/nlp/*.png, output/tables/*.csv
# ==============================================================================

library(tidyverse)
library(quanteda)
library(quanteda.textstats)
library(quanteda.textplots)
library(seededlda)
library(ldatuning)
library(topicmodels)
library(syuzhet)
library(stringi)
library(tidytext)
library(scales)

dir.create("output/figures/nlp",   showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables",        showWarnings = FALSE, recursive = TRUE)

ACCENT <- "steelblue"

save_fig <- function(plot, name, w = 9, h = 5.5, dpi = 200) {
  ggsave(file.path("output/figures/nlp", name),
         plot, width = w, height = h, dpi = dpi, bg = "white")
}


# ==============================================================================
# 1. Sentence-level corpora
# ==============================================================================
# We use paragraph splits from 02_preprocessing as the base unit for
# discourses (PDF formatting makes true sentence boundaries unreliable) and
# split Reddit posts/comments at sentence boundaries.

discursos <- readRDS("data/processed/discursos_paragraphs.rds")
reddit    <- readRDS("data/processed/reddit_cleaned.rds")

split_sentences <- function(text) {
  # Spanish sentence splitter: period / question / exclamation followed by
  # whitespace + capital. Falls back to the whole string when no split is
  # found, which keeps very short Reddit comments intact.
  stri_split_regex(text, "(?<=[.!?])\\s+(?=[A-ZÁÉÍÓÚÑ])")
}

# Discourses already arrive paragraph-by-paragraph; just rename for clarity.
sent_discursos <- discursos |>
  transmute(
    sentence_id = paragraph_id,
    doc_id,
    text
  )

sent_reddit <- reddit |>
  mutate(sentences = split_sentences(text)) |>
  unnest(sentences) |>
  filter(nchar(sentences) >= 15) |>
  transmute(
    sentence_id = row_number(),
    post_id,
    username,
    upVotes,
    text = sentences
  )


# ==============================================================================
# 2. Migration keyword exploration
# ==============================================================================
# Two questions: (a) how often does each corpus reach for migration-related
# language? (b) what do the surrounding sentences look like?

corpus_d <- readRDS("data/processed/discursos_corpus.rds")
corpus_r <- readRDS("data/processed/reddit_corpus.rds")
dfm_d    <- readRDS("data/processed/discursos_dfm.rds")
dfm_r    <- readRDS("data/processed/reddit_dfm.rds")

# --- 2a. Frequency of migration-related terms -------------------------------
migration_patterns <- c(
  "hait*",        # haiti, haitiano(s), haitiana(s)
  "migra*",       # migracion, migrante, migratoria
  "inmigra*",
  "fronter*",     # frontera, fronterizo
  "deport*",
  "refugi*",
  "muro",
  "ilegal*",
  "indocumenta*"
)

# textstat_frequency with a regex selection lets us pull per-corpus counts.
# We dictionary-lookup so wildcards collapse to one row per pattern.
mig_dict <- dictionary(list(
  haiti        = c("hait*"),
  migration    = c("migra*", "inmigra*"),
  border       = c("fronter*", "muro"),
  deportation  = c("deport*"),
  refugee      = c("refugi*"),
  illegal      = c("ilegal*", "indocumenta*")
))

freq_by_source <- function(dfm, source_label) {
  looked_up <- dfm_lookup(dfm, dictionary = mig_dict)
  tibble(
    source   = source_label,
    category = featnames(looked_up),
    count    = as.numeric(colSums(looked_up))
  ) |>
    mutate(rate_per_1k = 1000 * count / sum(ntoken(dfm)))
}

df_freq <- bind_rows(
  freq_by_source(dfm_d, "Presidential discourses"),
  freq_by_source(dfm_r, "Reddit (r/Dominicanos)")
)

write_csv(df_freq, "output/tables/migration_keyword_frequency.csv")

p_freq <- ggplot(df_freq,
                 aes(x = reorder(category, rate_per_1k), y = rate_per_1k)) +
  geom_col(fill = ACCENT, width = 0.7) +
  coord_flip() +
  facet_wrap(~ source, scales = "free_x") +
  labs(
    title = "Migration vocabulary: rate per 1,000 tokens",
    subtitle = "Presidential discourses vs. r/Dominicanos",
    x = NULL,
    y = "Mentions per 1,000 tokens"
  ) +
  theme_minimal(base_size = 12)

save_fig(p_freq, "01_migration_keyword_frequency.png")


# --- 2b. KWIC samples for the most loaded keyword (hait*) -------------------
toks_d <- tokens(corpus_d)
toks_r <- tokens(corpus_r)

kwic_d <- kwic(toks_d, pattern = "hait*", window = 6)
kwic_r <- kwic(toks_r, pattern = "hait*", window = 6)

# Save the first ~50 hits from each so we can inspect representative usage
# in the report appendix.
write_csv(as_tibble(head(kwic_d, 50)),
          "output/tables/kwic_haiti_discursos.csv")
write_csv(as_tibble(head(kwic_r, 50)),
          "output/tables/kwic_haiti_reddit.csv")


# ==============================================================================
# 3. Top-feature overview (wordcloud-style without the artwork)
# ==============================================================================
# Bar plots of top features are easier to read than wordclouds and easier to
# reproduce in print. We trim to the top 25 from each corpus.

top_feats <- function(dfm, source_label, n = 25) {
  tibble(
    word  = names(topfeatures(dfm, n)),
    count = as.numeric(topfeatures(dfm, n)),
    source = source_label
  )
}

df_top <- bind_rows(
  top_feats(dfm_d, "Presidential discourses"),
  top_feats(dfm_r, "Reddit (r/Dominicanos)")
)

p_top <- ggplot(df_top,
                aes(x = count, y = reorder_within(word, count, source))) +
  geom_col(fill = ACCENT) +
  scale_y_reordered() +
  facet_wrap(~ source, scales = "free") +
  labs(
    title = "Top 25 features per corpus (Spanish, stopwords removed)",
    x = "Frequency",
    y = NULL
  ) +
  theme_minimal(base_size = 11)

save_fig(p_top, "02_top_features_per_corpus.png", w = 11, h = 7)


# ==============================================================================
# 4. Topic modeling
# ==============================================================================
# We do two things per corpus:
#   (a) Sweep candidate K with ldatuning to pick a defensible number of
#       topics. We follow the report (Griffiths 2004) and use K = 6.
#   (b) Fit a seededlda model with seed words for migration-related topics,
#       and a residual catch-all topic. Seeded LDA is more interpretable
#       than vanilla LDA when we already know which themes we care about.

set.seed(1904)

# --- 4a. Candidate K diagnostics (one plot per corpus) ----------------------
sweep_k <- function(dfm, label) {
  res <- FindTopicsNumber(
    dfm,
    topics = seq(2, 12, by = 1),
    metrics = c("Griffiths2004", "CaoJuan2009",
                "Arun2010", "Deveaud2014"),
    method = "Gibbs",
    control = list(seed = 1904),
    mc.cores = 1L,
    verbose = FALSE
  )
  png(file.path("output/figures/nlp",
                paste0("03_topicnumber_", label, ".png")),
      width = 1200, height = 700, res = 150)
  FindTopicsNumber_plot(res)
  dev.off()
  res
}

# Discourses tend to be short and noisy paragraph-by-paragraph; aggregate to
# document level for the K sweep to give the metrics more text to work with.
dfm_d_doc <- dfm_group(dfm_d, groups = docvars(corpus_d, "doc_id"))
sweep_k(dfm_d_doc, "discursos")
sweep_k(dfm_r,     "reddit")


# --- 4b. Seeded LDA on each corpus ------------------------------------------
# Seed words are chosen to anchor topics around immigration, security,
# economy, identity, and political discourse. The `residual = TRUE` argument
# allows the model to discover one extra topic on its own.
seed_dict <- dictionary(list(
  haiti_migration = c("haiti*", "haitian*", "migra*", "inmigra*",
                      "frontera*", "fronteriz*", "muro", "deport*",
                      "refugi*", "indocumenta*"),
  security        = c("seguridad", "delincuen*", "violenci*", "crimen*",
                      "policia*", "militar*", "narco*"),
  economy         = c("econom*", "trabaj*", "empleo*", "salari*",
                      "pobreza", "inversion*", "industri*", "turism*"),
  health          = c("salud", "hospital*", "medic*", "sanitar*",
                      "covid*", "pandemi*"),
  identity        = c("dominican*", "patria", "nacion*", "cultura",
                      "raza", "negro*", "moreno*", "racis*")
))

fit_seeded <- function(dfm, k_residual = TRUE, label) {
  # Drop empty documents — seededlda errors if any row is all zeros after
  # the dictionary anchors don't appear.
  dfm <- dfm_subset(dfm, ntoken(dfm) > 0)
  model <- textmodel_seededlda(
    dfm,
    dictionary = seed_dict,
    residual   = k_residual,
    batch_size = 0.01
  )
  saveRDS(model,
          file.path("data/processed",
                    paste0("seededlda_", label, ".rds")))
  model
}

slda_d <- fit_seeded(dfm_d, label = "discursos")
slda_r <- fit_seeded(dfm_r, label = "reddit")


# --- 4c. Top words per seeded topic, plotted -------------------------------
plot_topic_words <- function(model, label, n = 12) {
  # terms() returns a matrix of top n words per topic; we melt to long.
  tw <- terms(model, n = n) |>
    as_tibble(.name_repair = "minimal") |>
    pivot_longer(everything(), names_to = "topic", values_to = "word") |>
    group_by(topic) |>
    mutate(rank = row_number()) |>
    ungroup()

  p <- ggplot(tw,
              aes(x = rank, y = reorder_within(word, -rank, topic))) +
    geom_col(fill = ACCENT) +
    scale_y_reordered() +
    facet_wrap(~ topic, scales = "free_y") +
    coord_cartesian(xlim = c(0, n + 1)) +
    labs(
      title = paste0("Seeded LDA topics — ", label),
      subtitle = "Top words per topic (Spanish; 1 = most representative)",
      x = "Rank within topic",
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_blank(),
          axis.ticks.x = element_blank())

  save_fig(p, paste0("04_topics_", label, ".png"), w = 11, h = 7)
}

plot_topic_words(slda_d, "discursos")
plot_topic_words(slda_r, "reddit")


# --- 4d. Topic proportions by corpus, weighted for Reddit ------------------
# For Reddit we weight each document by max(upVotes, 1) so a +200 post
# contributes proportionally more to the aggregated topic mix than a fresh
# comment with zero votes. This is the "weighted by upvotes" view.

topic_props <- function(model, weights = NULL, label) {
  th <- model$theta   # rows = docs, cols = topics
  if (is.null(weights)) weights <- rep(1, nrow(th))
  totals <- colSums(th * weights) / sum(weights)
  tibble(topic = colnames(th), proportion = totals, source = label)
}

# Match reddit posts back to upvote weights using the docnames quanteda kept.
reddit_docids <- as.integer(docnames(dfm_subset(dfm_r, ntoken(dfm_r) > 0)))
reddit_weights <- pmax(
  reddit$upVotes[match(reddit_docids, reddit$post_id)],
  1, na.rm = TRUE
)

df_props <- bind_rows(
  topic_props(slda_d, label = "Presidential discourses (uniform)"),
  topic_props(slda_r, label = "Reddit (uniform)"),
  topic_props(slda_r, weights = reddit_weights,
              label = "Reddit (weighted by upvotes)")
)

p_props <- ggplot(df_props,
                  aes(x = reorder(topic, proportion), y = proportion)) +
  geom_col(fill = ACCENT, width = 0.7) +
  coord_flip() +
  facet_wrap(~ source, scales = "free_x") +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title = "Topic prevalence per corpus",
    subtitle = "Reddit shown both uniformly and weighted by post upvotes",
    x = NULL,
    y = "Share of document-topic mass"
  ) +
  theme_minimal(base_size = 11)

save_fig(p_props, "05_topic_prevalence.png", w = 12, h = 6)


# ==============================================================================
# 5. Sentiment + negativity scoring (NRC Spanish lexicon)
# ==============================================================================
# get_nrc_sentiment() with language="spanish" maps each token to the eight
# NRC emotions plus positive/negative. We aggregate to the sentence level,
# then summarise per corpus.

score_sentiment <- function(sentences) {
  scores <- get_nrc_sentiment(sentences, language = "spanish")
  bind_cols(tibble(text = sentences), as_tibble(scores))
}

# Discourses sentiment
sent_disc_scores <- score_sentiment(sent_discursos$text) |>
  mutate(
    sentence_id = sent_discursos$sentence_id,
    doc_id      = sent_discursos$doc_id,
    negativity  = (negative - positive) /
                   pmax(positive + negative, 1)
  )

# Reddit sentiment — keep upvotes for the weighted aggregation.
sent_red_scores <- score_sentiment(sent_reddit$text) |>
  mutate(
    sentence_id = sent_reddit$sentence_id,
    post_id     = sent_reddit$post_id,
    upVotes     = sent_reddit$upVotes,
    negativity  = (negative - positive) /
                   pmax(positive + negative, 1)
  )

saveRDS(sent_disc_scores, "data/processed/sentiment_discursos.rds")
saveRDS(sent_red_scores,  "data/processed/sentiment_reddit.rds")


# --- 5a. NRC emotion counts per corpus -------------------------------------
emotion_cols <- c("anger", "anticipation", "disgust", "fear",
                  "joy", "sadness", "surprise", "trust")

emotion_summary <- function(df, source_label, weights = NULL) {
  if (is.null(weights)) weights <- rep(1, nrow(df))
  df |>
    select(all_of(emotion_cols)) |>
    mutate(across(everything(), \(x) x * weights)) |>
    summarise(across(everything(), sum)) |>
    pivot_longer(everything(),
                 names_to = "emotion", values_to = "count") |>
    mutate(
      source = source_label,
      share  = count / sum(count)
    )
}

df_emotions <- bind_rows(
  emotion_summary(sent_disc_scores, "Presidential discourses"),
  emotion_summary(sent_red_scores,  "Reddit (uniform)"),
  emotion_summary(sent_red_scores,  "Reddit (weighted by upvotes)",
                  weights = pmax(sent_red_scores$upVotes, 1, na.rm = TRUE))
)

p_emo <- ggplot(df_emotions,
                aes(x = reorder(emotion, share), y = share)) +
  geom_col(fill = ACCENT, width = 0.7) +
  coord_flip() +
  facet_wrap(~ source, scales = "free_x") +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title = "NRC emotion profile per corpus",
    subtitle = "Share of NRC-classified emotion tokens",
    x = NULL,
    y = "Share of emotion mentions"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"))

save_fig(p_emo, "06_nrc_emotions.png", w = 12, h = 6)


# --- 5b. Negativity distribution ------------------------------------------
df_neg <- bind_rows(
  sent_disc_scores |>
    transmute(negativity, source = "Presidential discourses"),
  sent_red_scores |>
    transmute(negativity, source = "Reddit (r/Dominicanos)")
)

p_neg <- ggplot(df_neg, aes(x = negativity)) +
  geom_histogram(fill = ACCENT, bins = 40, color = "white", linewidth = 0.2) +
  facet_wrap(~ source, scales = "free_y") +
  labs(
    title = "Sentence-level negativity score by corpus",
    subtitle = "Score = (negative − positive) / (negative + positive); range [-1, 1]",
    x = "Negativity score",
    y = "Number of sentences"
  ) +
  theme_minimal(base_size = 11)

save_fig(p_neg, "07_negativity_distribution.png", w = 11, h = 5)


# --- 5c. Negativity around migration keywords ------------------------------
# A simple question: when each corpus uses migration vocabulary, is the
# surrounding sentence more negative than the corpus baseline?
flag_mig <- function(text) {
  str_detect(tolower(stri_trans_general(text, "Latin-ASCII")),
             "haiti|migra|inmigra|fronter|deport|refugi|indocumenta|muro")
}

df_neg_mig <- bind_rows(
  sent_disc_scores |>
    mutate(source = "Presidential discourses",
           is_migration = flag_mig(text)),
  sent_red_scores |>
    mutate(source = "Reddit (r/Dominicanos)",
           is_migration = flag_mig(text))
) |>
  group_by(source, is_migration) |>
  summarise(mean_neg = mean(negativity, na.rm = TRUE),
            n = n(), .groups = "drop") |>
  mutate(label = if_else(is_migration,
                         "Migration sentences",
                         "All other sentences"))

p_neg_mig <- ggplot(df_neg_mig,
                    aes(x = label, y = mean_neg)) +
  geom_col(fill = ACCENT, width = 0.6) +
  geom_hline(yintercept = 0, color = "grey40", linetype = "dashed") +
  facet_wrap(~ source) +
  geom_text(aes(label = paste0("n = ", comma(n))),
            vjust = -0.3, size = 3.2, color = "grey30") +
  labs(
    title = "Average negativity inside vs. outside migration sentences",
    subtitle = "Migration sentences contain any of: haiti*, migra*, fronter*, deport*, refugi*, …",
    x = NULL,
    y = "Mean negativity score"
  ) +
  theme_minimal(base_size = 11)

save_fig(p_neg_mig, "08_negativity_around_migration.png", w = 11, h = 5)


message("NLP pipeline complete. Outputs in output/figures/nlp/ and ",
        "output/tables/.")
