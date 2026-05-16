# NLP: keyword exploration, seeded LDA (k=6), NRC sentiment + negativity.
# Spanish text, English code. Reddit aggregations weighted by upvotes.

library(tidyverse); library(quanteda); library(seededlda); library(ldatuning)
library(syuzhet); library(tidytext); library(scales)

dir.create("output/figures/nlp", showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables", showWarnings = FALSE, recursive = TRUE)
ACC <- "steelblue"
save_fig <- \(p, f, w = 10, h = 6) ggsave(file.path("output/figures/nlp", f),
                                          p, width = w, height = h, dpi = 200, bg = "white")

corpus_d <- readRDS("data/processed/discursos_corpus.rds")
corpus_r <- readRDS("data/processed/reddit_corpus.rds")
dfm_d    <- readRDS("data/processed/discursos_dfm.rds")
dfm_r    <- readRDS("data/processed/reddit_dfm.rds")
reddit   <- readRDS("data/processed/reddit_cleaned.rds")
discursos <- readRDS("data/processed/discursos_paragraphs.rds")

# --- Migration keyword rate + KWIC dumps (hait*) ------------------------------
mig <- dictionary(list(haiti = "hait*", migration = c("migra*","inmigra*"),
                       border = c("fronter*","muro"), deportation = "deport*",
                       refugee = "refugi*", illegal = c("ilegal*","indocumenta*")))
rate <- \(dfm, src) tibble(category = names(colSums(dfm_lookup(dfm, mig))),
                            count = colSums(dfm_lookup(dfm, mig)),
                            rate = 1000 * count / sum(ntoken(dfm)), source = src)
freq <- bind_rows(rate(dfm_d, "Discourses"), rate(dfm_r, "Reddit"))
write_csv(freq, "output/tables/migration_keyword_frequency.csv")
save_fig(ggplot(freq, aes(reorder(category, rate), rate)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() + facet_wrap(~ source, scales = "free_x") +
  labs(title = "Migration vocabulary: rate per 1,000 tokens", x = NULL, y = NULL) +
  theme_minimal(), "01_migration_keyword_frequency.png")
write_csv(as_tibble(head(kwic(tokens(corpus_d), "hait*", 6), 50)), "output/tables/kwic_haiti_discursos.csv")
write_csv(as_tibble(head(kwic(tokens(corpus_r), "hait*", 6), 50)), "output/tables/kwic_haiti_reddit.csv")

# --- Optimal K diagnostic (Griffiths/CaoJuan/Arun/Deveaud) --------------------
sweep_k <- \(dfm, label) {
  r <- FindTopicsNumber(dfm, 2:10, c("Griffiths2004","CaoJuan2009","Arun2010","Deveaud2014"),
                        method = "Gibbs", control = list(seed = 1904), verbose = FALSE)
  png(file.path("output/figures/nlp", paste0("02_topicnumber_", label, ".png")),
      1200, 700, res = 150); FindTopicsNumber_plot(r); dev.off()
}
sweep_k(dfm_group(dfm_d, groups = docvars(corpus_d, "doc_id")), "discursos")
sweep_k(dfm_r, "reddit")

# --- Seeded LDA: 5 seeded + 1 residual = 6 topics (Griffiths 2004) ------------
seeds <- dictionary(list(
  haiti_migration = c("haiti*","haitian*","migra*","inmigra*","frontera*","deport*","refugi*","muro"),
  security = c("seguridad","delincuen*","violenci*","crimen*","policia*","militar*","narco*"),
  economy  = c("econom*","trabaj*","empleo*","salari*","pobreza","inversion*","industri*","turism*"),
  health   = c("salud","hospital*","medic*","sanitar*","covid*","pandemi*"),
  identity = c("dominican*","patria","nacion*","cultura","raza","negro*","racis*")))
fit_lda <- \(dfm) textmodel_seededlda(dfm_subset(dfm, ntoken(dfm) > 0),
                                       seeds, residual = TRUE, batch_size = 0.01)
set.seed(1904); slda_d <- fit_lda(dfm_d); slda_r <- fit_lda(dfm_r)
saveRDS(slda_d, "data/processed/seededlda_discursos.rds")
saveRDS(slda_r, "data/processed/seededlda_reddit.rds")

plot_topics <- \(m, label) save_fig(terms(m, 12) |> as_tibble(.name_repair = "minimal") |>
  pivot_longer(everything(), names_to = "topic", values_to = "word") |>
  group_by(topic) |> mutate(rank = 13 - row_number()) |> ungroup() |>
  ggplot(aes(rank, reorder_within(word, rank, topic))) +
  geom_col(fill = ACC) + scale_y_reordered() + facet_wrap(~ topic, scales = "free_y") +
  labs(title = paste("Seeded LDA topics —", label), x = "Rank", y = NULL) +
  theme_minimal(), paste0("03_topics_", label, ".png"), w = 11, h = 7)
plot_topics(slda_d, "discursos"); plot_topics(slda_r, "reddit")

# --- Topic prevalence (Reddit also weighted by upvotes) -----------------------
prev <- \(m, w, src) tibble(topic = colnames(m$theta), source = src,
                            share = colSums(m$theta * w) / sum(w))
red_ids <- as.integer(docnames(dfm_subset(dfm_r, ntoken(dfm_r) > 0)))
red_w   <- pmax(reddit$upVotes[match(red_ids, reddit$post_id)], 1, na.rm = TRUE)
save_fig(bind_rows(prev(slda_d, rep(1, nrow(slda_d$theta)), "Discourses"),
                   prev(slda_r, rep(1, nrow(slda_r$theta)), "Reddit (uniform)"),
                   prev(slda_r, red_w, "Reddit (upvote-weighted)")) |>
  ggplot(aes(reorder(topic, share), share)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() +
  facet_wrap(~ source, scales = "free_x") +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title = "Topic prevalence per corpus", x = NULL, y = NULL) +
  theme_minimal(), "04_topic_prevalence.png")

# --- NRC sentiment + continuous negativity ------------------------------------
nrc_d <- bind_cols(discursos["text"], get_nrc_sentiment(discursos$text, "spanish")) |>
  mutate(neg = (negative - positive) / pmax(positive + negative, 1), source = "Discourses")
nrc_r <- bind_cols(reddit[c("text","upVotes")], get_nrc_sentiment(reddit$text, "spanish")) |>
  mutate(neg = (negative - positive) / pmax(positive + negative, 1), source = "Reddit")
saveRDS(nrc_d, "data/processed/sentiment_discursos.rds")
saveRDS(nrc_r, "data/processed/sentiment_reddit.rds")

emo_cols <- c("anger","anticipation","disgust","fear","joy","sadness","surprise","trust")
emo <- \(df, w, src) df |> select(all_of(emo_cols)) |>
  mutate(across(everything(), \(x) x * w)) |> summarise(across(everything(), sum)) |>
  pivot_longer(everything(), names_to = "emotion", values_to = "n") |>
  mutate(share = n / sum(n), source = src)
save_fig(bind_rows(emo(nrc_d, 1, "Discourses"),
                   emo(nrc_r, 1, "Reddit (uniform)"),
                   emo(nrc_r, pmax(nrc_r$upVotes, 1, na.rm = TRUE), "Reddit (upvote-weighted)")) |>
  ggplot(aes(reorder(emotion, share), share)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() +
  facet_wrap(~ source, scales = "free_x") +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title = "NRC emotion profile per corpus", x = NULL, y = NULL) +
  theme_minimal(), "05_nrc_emotions.png")

flag <- \(t) str_detect(tolower(t), "haiti|migra|inmigra|fronter|deport|refugi|indocumenta|muro")
save_fig(bind_rows(nrc_d |> mutate(mig = flag(text)), nrc_r |> mutate(mig = flag(text))) |>
  group_by(source, mig) |> summarise(mean_neg = mean(neg), n = n(), .groups = "drop") |>
  ggplot(aes(if_else(mig, "Migration", "Others"), mean_neg)) +
  geom_col(fill = ACC, width = 0.6) + facet_wrap(~ source) +
  geom_hline(yintercept = 0, color = "grey40", linetype = "dashed") +
  geom_text(aes(label = paste0("n=", comma(n))), vjust = -0.4, size = 3) +
  labs(title = "Negativity inside vs. outside migration sentences",
       x = NULL, y = "Mean negativity") + theme_minimal(),
  "06_negativity_around_migration.png", w = 10, h = 5)
