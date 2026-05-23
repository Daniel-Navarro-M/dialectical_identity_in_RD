# Topic modeling on r/Dominicanos at the sentence level. Two complementary
# views:
#
#   1. Seeded LDA — anchored to five theoretical themes (haiti_migration,
#      security, economy, health, identity) plus one residual. Tests H2
#      directly: are there latent topics around security and Haitian-framing?
#
#   2. Unseeded LDA at the same K, same hyperparameters, no anchor
#      dictionary. Validates that the haiti/migration cluster is in the data
#      rather than imposed by the seeds.
#
#   3. DBSCAN on the TF-IDF SVD projection, density-based clustering. Unlike
#      LDA and Kmeans DBSCAN does not require a fixed K and explicitly identifies noise
#      points. Used as an alternative exploratory lens.
#

# Requires: install.packages("dbscan") if not already installed.

rm(list = ls())

library(tidyverse)
library(quanteda)
library(seededlda)
library(tidytext)
library(scales)
library(dbscan)

dir.create("output/figures/nlp", showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables",       showWarnings = FALSE, recursive = TRUE)

ACC <- "steelblue"
OUT <- "output/figures/nlp"

THEME <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(color = "black", size = 10),
    plot.caption     = element_text(color = "black", size = 9, hjust = 0),
    axis.title       = element_text(size = 10),
    axis.text        = element_text(size = 9),
    panel.grid.minor = element_blank(),
    strip.text       = element_text(face = "bold"),
    legend.position  = "top"
  )

corpus_r <- readRDS("data/processed/reddit_corpus.rds")
dfm_r <- readRDS("data/processed/reddit_dfm.rds")
sent_r <- readRDS("data/processed/reddit_sentences.rds")

# Migration keyword frequency ----

mig <- dictionary(list(
  haiti = c("hait*","aytian*"),
  foreigners = "extranjer*",
  inmigration = c("inmigra*", "inmigracion", "inmigrantes"),
  migration = c("migra*",   "migracion",   "migrantes"),
  border = c("fronter*", "muro"),
  deportation = "deport*",
  refugee = "refugi*",
  ilegal = c("ilegal*", "indocumenta*")
))

dfm_d <- readRDS("data/processed/discursos_dfm.rds")
rate  <- \(dfm, src) tibble(
  category = names(colSums(dfm_lookup(dfm, mig))),
  count = colSums(dfm_lookup(dfm, mig)),
  rate = 1000 * count / sum(ntoken(dfm)),
  source = src
)
freq <- bind_rows(rate(dfm_d, "Discourses"), rate(dfm_r, "Reddit"))
freq
write_csv(freq, "output/tables/migration_keyword_frequency.csv")

p1 <- ggplot(freq, aes(reorder(category, rate), rate)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() +
  facet_wrap(~ source) + coord_flip(ylim = c(0, 25)) +
  labs(title = "Migration vocabulary: rate per 1,000 tokens",
       x = NULL, y = NULL) +
  THEME

ggsave(file.path(OUT, "01_keyword_frequency.png"), p1,
       width = 10, height = 6, dpi = 200, bg = "white")


# Seeded LDA + unseeded LDA validation ----

# K = 6 is fixed ad hoc.
# DFMs because the per-document term counts are low, the metrics disagree.
# Hardcoding K is more defensible than reporting unstable sweep results.

K_REDDIT <- 6

seeds <- dictionary(list(
  haiti_migration = c("haiti*","haitian*","migra*","inmigra*","frontera*",
                      "deport*","refugi*","muro"),
  security        = c("seguridad","delincuen*","violenci*","crimen*",
                      "policia*","militar*","narco*","band*", "defens*",
                      "pandill*", "vigi*"),
  economy         = c("econom*","trabaj*","empleo*","salari*","pobreza",
                      "inversion*","industri*","turism*", "miner*"),
  health          = c("salud","hospital*","medic*","sanitar*","covid*",
                      "pandemi*", "docto*", "clinic*", "enferm*", "part*"),
  identity        = c("dominican*","patria","nacion*","cultura","raza",
                      "negro*","racis*","isla")
))

dfm_r_lda <- dfm_subset(dfm_r, ntoken(dfm_r) > 0)
set.seed(1905) #changed the seed to the year where the ruso japanese war ended
slda_r <- textmodel_seededlda(dfm_r_lda, seeds, residual = TRUE,
                              batch_size = 0.01)
lda_r  <- textmodel_lda(dfm_r_lda, k = K_REDDIT, batch_size = 0.01)

saveRDS(slda_r, "data/processed/seededlda_reddit_sent.rds")
saveRDS(lda_r,  "data/processed/lda_reddit_sent.rds")

# Top words per topic side-by-side. If the unseeded model used as validation.
plot_topics <- function(model, label, fname, w = 11, h = 7) {
  tw <- terms(model, 12) |>
    as_tibble(.name_repair = "minimal") |>
    pivot_longer(everything(), names_to = "topic", values_to = "word") |>
    group_by(topic) |> mutate(rank = 13 - row_number()) |> ungroup()
  p <- ggplot(tw, aes(rank, reorder_within(word, rank, topic))) +
    geom_col(fill = ACC) + scale_y_reordered() +
    facet_wrap(~ topic, scales = "free_y") +
    labs(title = paste("Top words per topic: Reddit (", label, ")", sep = ""),
         x = "Rank within topic", y = NULL) +
    THEME
  ggsave(file.path(OUT, fname), p, width = w, height = h, dpi = 200, bg = "white")
}

plot_topics(slda_r, "Seeded LDA",   "02_topics_seeded.png")
plot_topics(lda_r,  "Unseeded LDA", "02b_topics_unseeded.png")


# Topic prevalence: column-means of theta (the per-document topic distribution
# matrix) give the share of total document-topic mass each topic captures.
# At sentence level the distribution is flat because each sentence has few
# tokens: read the numbers comparatively, not as absolute mass.
prev <- tibble(topic = colnames(slda_r$theta),
               share = colMeans(slda_r$theta))
write_csv(prev, "output/tables/topic_prevalence_reddit.csv")

p_prev <- ggplot(prev, aes(reorder(topic, share), share)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title = "Topic prevalence — Reddit (seeded LDA)",
       x = NULL, y = "Share of document-topic mass") +
  THEME

ggsave(file.path(OUT, "03_topic_prevalence.png"), p_prev,
       width = 10, height = 6, dpi = 200, bg = "white")

# Top three representative sentences per seeded topic
# Each sentence is shown with its theta probability for the topic; these are
# the qualitative anchors for naming the topics in the article.
theta_df <- as_tibble(slda_r$theta, rownames = "sentence_index") |>
  mutate(sentence_index = as.integer(sentence_index))

top_sents <- map_dfr(colnames(slda_r$theta), function(tp) {
  theta_df |>
    select(sentence_index, share = all_of(tp)) |>
    slice_max(share, n = 3) |>
    left_join(sent_r |> select(sentence_index, text), by = "sentence_index") |>
    mutate(topic = tp)
})

cat("\n========= TOP 3 REPRESENTATIVE SENTENCES PER TOPIC =========\n")
for (tp in colnames(slda_r$theta)) {
  cat("\n--- topic: ", tp, " ---\n", sep = "")
  rows <- top_sents |> filter(topic == tp)
  for (i in seq_len(nrow(rows))) {
    cat("  [theta=", round(rows$share[i], 3), "]  ",
        rows$text[i], "\n\n", sep = "")
  }
}


# DBSCAN clustering on TF-IDF / truncated SVD ----
# Alternative exploration: density-based clustering does not require a fixed
# number of clusters and labels low-density points as noise (cluster 0).
# It answers a different question than LDA: not "what theme mixture does this
# sentence have?" but "is this sentence in a dense region of word-similar
# sentences?"
# Tuning: eps comes from inspecting the k-NN distance plot. A natural elbow
# in the sorted k-distance curve is the recommended choice. minPts ~ 2*dim
# Probably not very useful, likely should use K means or something simplier

top_feats <- names(topfeatures(dfm_r_lda, 1000))
dfm_r_top <- dfm_select(dfm_r_lda, top_feats, selection = "keep")

m_tfidf <- as.matrix(dfm_tfidf(dfm_r_top))
sv      <- svd(m_tfidf, nu = 30, nv = 0)
emb_svd <- sv$u

## k-NN distance plot for eps selection ----
png(file.path(OUT, "04_dbscan_knn_dist.png"), 1000, 600, res = 150)
dbscan::kNNdistplot(emb_svd, k = 30)
abline(h = 0.041, lty = 2, col = "grey50")
title(main = "DBSCAN tuning: 30-NN distance plot",
      sub  = "Pick eps at the elbow of the sorted distance curve")
dev.off()

## DBSCAN with starting parameters ----
db <- dbscan::dbscan(emb_svd, eps = 0.041, minPts = 30)
print(table(db$cluster))

# Attach cluster labels back to the sentence-level data
sent_clustered <- sent_r |>
  semi_join(tibble(sentence_index = as.integer(docnames(dfm_r_lda))),
            by = "sentence_index") |>
  mutate(cluster = db$cluster)

saveRDS(sent_clustered, "data/processed/reddit_sentences_dbscan.rds")


## Top words per DBSCAN cluster ----
cluster_words <- sent_clustered |>
  filter(cluster > 0) |>
  select(sentence_index, cluster, text) |>
  unnest_tokens(word, text) |>
  filter(nchar(word) > 2, !word %in% stopwords("es")) |>
  count(cluster, word, sort = TRUE) |>
  group_by(cluster) |>
  slice_max(n, n = 10) |>
  ungroup()

for (k in sort(unique(cluster_words$cluster))) {
  cat("\n--- cluster ", k, " (",
      sum(sent_clustered$cluster == k), " sentences) ---\n", sep = "")
  print(cluster_words |> filter(cluster == k) |> pull(word))
}

p_dbscan <- cluster_words |>
  mutate(cluster_lbl = paste("Cluster", cluster)) |>
  ggplot(aes(n, reorder_within(word, n, cluster_lbl))) +
  geom_col(fill = ACC) + scale_y_reordered() +
  facet_wrap(~ cluster_lbl, scales = "free") +
  labs(title = "Top 10 words per DBSCAN cluster (Reddit)",
       subtitle = "Density-based clusters in TF-IDF / SVD space; cluster 0 (noise) excluded",
       x = "Frequency", y = NULL) +
  THEME

ggsave(file.path(OUT, "05_dbscan_top_words.png"), p_dbscan,
       width = 11, height = 7, dpi = 200, bg = "white")
