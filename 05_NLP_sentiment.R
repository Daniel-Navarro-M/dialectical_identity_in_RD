# Sentiment analysis using a Spanish transformer (pysentimiento/robertuito,
# a RoBERTa fine-tuned on Spanish social media). 

rm(list = ls())

library(tidyverse)
library(reticulate)
library(text)
library(scales)

Sys.setenv(RETICULATE_CONDA = "D:/conda/Scripts/conda.exe") # this must be changed
# according to user's conda installation.

textrpp_initialize()

dir.create("output/figures/nlp", showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables",       showWarnings = FALSE, recursive = TRUE)

ACC <- "steelblue"
OUT <- "output/figures/nlp"

THEME <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(color = "grey40", size = 10),
    plot.caption     = element_text(color = "grey50", size = 9, hjust = 0),
    axis.title       = element_text(size = 10),
    axis.text        = element_text(size = 9),
    panel.grid.minor = element_blank(),
    strip.text       = element_text(face = "bold"),
    legend.position  = "top"
  )


# --- Loading data and run the transformer ----

sent_r <- readRDS("data/processed/reddit_sentences.rds")
sent_d <- readRDS("data/processed/discursos_sentences.rds")

sentences <- bind_rows(sent_d, sent_r) |>
  select(corpus, sentence_index, sentence_within_doc, doc_id,
         post_id, date, title, username, dataType, upVotes, text)

saveRDS(sentences, "data/processed/sentences.rds")

df <- readRDS("data/processed/sentences.rds")
cat("Sentences per corpus:\n"); print(count(df, corpus))

transformers <- reticulate::import("transformers")

# top_k = NULL returns the full probability distribution over POS/NEU/NEG
# truncation = TRUE handles sentences that exceed the model's 128-BPE-
# token limit; a long sentence is scored on its first 128 tokens rather than
# erroring out.
sentiment_pipeline <- transformers$pipeline(
  "sentiment-analysis",
  model      = "pysentimiento/robertuito-sentiment-analysis",
  device     = 0L, # I am using 0L because I have an Nvidia GPU, to do by CPU use -1L
  top_k      = NULL,
  truncation = TRUE
)

# Batched inference. Batch size 64 is the default robertuito ships with;
# increase if you have GPU/VRAM headroom, decrease if you hit OOM.
batch_size <- 254L
results    <- list()
for (i in seq(1, nrow(df), by = batch_size)) {
  batch <- df$text[i:min(i + batch_size - 1L, nrow(df))]
  results[[length(results) + 1]] <- sentiment_pipeline(batch)
}

# Each result row is a list of three {label, score} dicts. Reshape to wide
# columns of p_pos / p_neu / p_neg.
sent_res <- map_dfr(unlist(results, recursive = FALSE), function(r) {
  probs <- setNames(map_dbl(r, "score"), map_chr(r, "label"))
  tibble(p_pos = probs[["POS"]],
         p_neu = probs[["NEU"]],
         p_neg = probs[["NEG"]])
})
stopifnot(nrow(sent_res) == nrow(df))

df <- df |>
  bind_cols(sent_res) |>
  mutate(positivity_score = p_pos + 0.5 * p_neu,
         negativity_score = 1 - positivity_score,
         label = case_when(p_pos > p_neg & p_pos > p_neu ~ "Positive",
                           p_neg > p_pos & p_neg > p_neu ~ "Negative",
                           TRUE                           ~ "Neutral"))

saveRDS(df, "data/processed/sentences_with_sentiment.rds")

# ---- Positivity distribution per corpus ----

# Boxplot rather than histogram because we are comparing two corpora directly
# and the shape comparison (median, IQR, tails) is what matters.

p_box <- ggplot(df, aes(x = reorder(corpus, positivity_score),
                        y = positivity_score, fill = corpus)) +
  geom_boxplot(outlier.alpha = 0.2) +
  scale_fill_manual(values = c(Discourses = ACC, Reddit = "grey70")) +
  labs(title    = "Positivity distribution by corpus",
       subtitle = "robertuito sentiment, sentence level (0 = Negative, 1 = Positive)",
       x = NULL, y = "Positivity score") +
  THEME + theme(legend.position = "none")

ggsave(file.path(OUT, "06_positivity_boxplot.png"), p_box,
       width = 9, height = 5.5, dpi = 200, bg = "white")



# ---- Narrative arc: positivity over the sentence sequence ----
# Raw transformer scores cluster near 0 and 1 (the model is confident), so the
# scatter is bimodal. The LOESS line smooths over this and shows whether
# average positivity rises, falls, or stays steady as each corpus progresses.

p_arc <- ggplot(df, aes(x = sentence_index, y = positivity_score, color = corpus)) +
  geom_point(alpha = 0.05) +
  geom_smooth(method = "loess", se = FALSE, span = 0.2, linewidth = 1.2) +
  facet_wrap(~ corpus, scales = "free_x") +
  scale_color_manual(values = c(Discourses = ACC, Reddit = "#E4003B")) +
  labs(title    = "Narrative arc of positivity",
       subtitle = "Smoothed sentiment over the sentence sequence (per corpus)",
       x = "Sentence sequence (start to finish)",
       y = "Positivity score") +
  THEME

ggsave(file.path(OUT, "07_narrative_arc.png"), p_arc,
       width = 11, height = 5.5, dpi = 200, bg = "white")



# ---- Class share per corpus ----

shares <- df |> count(corpus, label) |>
  group_by(corpus) |> mutate(share = n / sum(n))
write_csv(shares, "output/tables/sentiment_class_shares.csv")

p_shares <- ggplot(shares, aes(label, share, fill = label)) +
  geom_col(width = 0.7) + facet_wrap(~ corpus) +
  scale_fill_manual(values = c(Positive = "grey70",
                               Neutral  = "grey50",
                               Negative = ACC)) +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title = "Sentiment class shares per corpus",
       x = NULL, y = NULL) +
  THEME + theme(legend.position = "none")

ggsave(file.path(OUT, "08_sentiment_shares.png"), p_shares,
       width = 11, height = 5, dpi = 200, bg = "white")
# surprise to no one reddit is mostly negative

# this already reveals that there is a majority of negative sentiments around
# the haitian and migration narrative


# ---- H1: negativity in migration-vocabulary sentences vs. the rest ----
# did not use extranjero (foreigner) as it is too broad. Having it also reduces 
# the negativity by 0.01 points, which might indicate that the negative sentiment
# is not so general when refering to foreigners
# Keyword set tightened to Haiti + immigration specifically. Excludes


flag_mig <- \(t) str_detect(
  tolower(t),
  "haiti|haitian|inmigra|migra|fronter|deport|indocumenta|refugiad|ilega"
)

h1 <- df |> mutate(mig = flag_mig(text)) |>
  group_by(corpus, mig) |>
  summarise(mean_pos = mean(positivity_score, na.rm = TRUE),
            mean_neg = mean(negativity_score, na.rm = TRUE),
            n = n(), .groups = "drop") |>
  mutate(group = if_else(mig, "Migration", "Non-migration"))
write_csv(h1, "output/tables/h1_migration_negativity.csv")


p_h1 <- ggplot(h1, aes(group, mean_neg)) +
  geom_col(fill = ACC, width = 0.6) + facet_wrap(~ corpus) +
  geom_text(aes(label = paste0("n=", comma(n))),
            vjust = -0.4, size = 3, color = "grey30") +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title = "H1: mean negativity in migration vs. non-migration sentences",
       x = NULL, y = "Mean negativity (= 1 - positivity)") +
  THEME

ggsave(file.path(OUT, "09_h1_migration_negativity.png"), p_h1,
       width = 11, height = 5, dpi = 200, bg = "white")



flag_mig <- \(t) str_detect(
  tolower(t),
  "haiti|haitian|inmigra|migra|fronter|deport|indocumenta|refugiad|ilega"
)

# Per-sentence data for the violin
h1_long <- df |> mutate(mig = flag_mig(text),
                        group = if_else(mig, "Migration", "Non-migration"))

# Summary used for the n labels and the CSV
h1 <- h1_long |>
  group_by(corpus, group) |>
  summarise(mean_pos = mean(positivity_score, na.rm = TRUE),
            mean_neg = mean(negativity_score, na.rm = TRUE),
            n = n(), .groups = "drop")
write_csv(h1, "output/tables/h1_migration_negativity.csv")

p_h1 <- ggplot(h1_long, aes(group, negativity_score, fill = group)) +
  geom_violin(alpha = 0.7, trim = FALSE) +
  geom_boxplot(width = 0.1, fill = "white", outlier.shape = NA) +
  facet_wrap(~ corpus) +
  scale_fill_manual(values = c(Migration = ACC, `Non-migration` = "grey75")) +
  scale_y_continuous(limits = c(-0.3, 1.3), breaks = seq(0, 1, 0.2)) +
  geom_text(data = h1, aes(x = group, y = 1.05, label = paste0("n=", comma(n))),
            size = 3, color = "grey30", inherit.aes = FALSE) +
  labs(title    = "H1: negativity in migration vs. non-migration sentences",
       subtitle = "0 = fully positive · 0.5 = neutral · 1 = fully negative",
       x = NULL, y = "Negativity score") +
  THEME + theme(legend.position = "none")

ggsave(file.path(OUT, "09_h1_migration_negativity.png"), p_h1,
       width = 11, height = 5, dpi = 200, bg = "white")

# ---- Sentiment per migration keyword (Reddit only) ----
# Per-keyword negativity makes the H1 result interpretable: which family of
# migration vocabulary carries the strongest negative load? The lookbehind on
# "migra" prevents double-counting "inmigra" and "emigra".

keywords <- c(
  `hait*` = "hait",
  inmigr = "inmigra",
  migra = "(?<![ie])migra",
  fronter = "fronter",
  deport = "deport",
  muro = "\\bmuro\\b",
  indocumenta = "indocumenta",
  extranje = "extranjer"
)

by_kw_long <- imap_dfr(keywords, \(re, name) df |>
                         filter(corpus == "Reddit", str_detect(tolower(text), re)) |>
                         mutate(keyword = name)
)

# Summary for the n labels and CSV
by_kw <- by_kw_long |>
  group_by(keyword) |>
  summarise(mean_neg = mean(negativity_score, na.rm = TRUE),
            n = n(), .groups = "drop")
write_csv(by_kw, "output/tables/sentiment_by_keyword.csv")

# Order keywords by mean negativity so the worst is at one end
keyword_order <- by_kw |> arrange(mean_neg) |> pull(keyword)
by_kw_long <- by_kw_long |> mutate(keyword = factor(keyword, levels = keyword_order))
by_kw      <- by_kw      |> mutate(keyword = factor(keyword, levels = keyword_order))

p_kw <- ggplot(by_kw_long, aes(keyword, negativity_score)) +
  geom_violin(fill = ACC, alpha = 0.7, trim = FALSE) +
  geom_boxplot(width = 0.1, fill = "white", outlier.shape = NA) +
  geom_text(data = by_kw, aes(x = keyword, y = 1.05, label = paste0("n=", comma(n))),
            size = 3, color = "grey30", inherit.aes = FALSE) +
  coord_flip() +
  scale_y_continuous(limits = c(0, 1.12), breaks = seq(0, 1, 0.2)) +
  labs(title    = "Reddit: negativity distribution per Haiti+immigration keyword",
       subtitle = "0 = fully positive · 0.5 = neutral · 1 = fully negative",
       x = NULL, y = "Negativity score") +
  THEME

ggsave(file.path(OUT, "10_negativity_per_keyword.png"), p_kw,
       width = 11, height = 7, dpi = 340, bg = "white")


# ---- Sentiment crossed with seeded-LDA topic (Reddit) ----

# Each Reddit sentence has a 6-dimensional theta vector from the seeded LDA
# The dominant topic for a sentence is the argmax of theta — the
# topic the model assigns the highest probability mass to.

slda <- readRDS("data/processed/seededlda_reddit_sent.rds")

dominant <- as_tibble(slda$theta, rownames = "sentence_index") |>
  mutate(sentence_index = as.integer(sentence_index)) |>
  pivot_longer(-sentence_index, names_to = "topic", values_to = "share") |>
  group_by(sentence_index) |>
  slice_max(share, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(sentence_index, topic)

reddit_with_topic <- df |>
  filter(corpus == "Reddit") |>
  inner_join(dominant, by = "sentence_index")

topic_sent <- reddit_with_topic |>
  group_by(topic) |>
  summarise(mean_neg = mean(negativity_score),
            median_neg = median(negativity_score),
            n = n(),
            .groups = "drop")
write_csv(topic_sent, "output/tables/sentiment_by_topic.csv")

p_topic_box <- ggplot(reddit_with_topic,
                      aes(reorder(topic, negativity_score, FUN = median),
                          negativity_score)) +
  geom_violin(fill = ACC, alpha = 0.7, trim = FALSE) +
  geom_boxplot(width = 0.1, fill = "white", outlier.shape = NA) +
  coord_flip() +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title    = "Reddit: negativity distribution per seeded-LDA topic",
       subtitle = "Each sentence assigned its dominant topic; box shows IQR, line shows median",
       x = NULL, y = "Negativity") +
  THEME

ggsave(file.path(OUT, "12_negativity_per_topic_boxplot.png"), p_topic_box,
       width = 10, height = 6, dpi = 200, bg = "white")