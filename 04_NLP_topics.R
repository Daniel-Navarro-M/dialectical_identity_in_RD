# NLP topic analysis: migration keywords, KWIC, K-sweep diagnostic,
# seeded LDA per corpus, and migration framing (H2) on presidential discourse.
# Sentiment analysis is in 05_NLP_sentiment.R.

library(tidyverse); library(quanteda); library(seededlda); library(ldatuning)
library(tidytext); library(scales)

dir.create("output/figures/nlp", showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables", showWarnings = FALSE, recursive = TRUE)
ACC <- "steelblue"
save_fig <- \(p, f, w = 10, h = 6) ggsave(file.path("output/figures/nlp", f),
                                          p, width = w, height = h, dpi = 200, bg = "white")

corpus_d <- readRDS("data/processed/discursos_corpus.rds")
corpus_r <- readRDS("data/processed/reddit_corpus.rds")
dfm_d    <- readRDS("data/processed/discursos_dfm.rds")
dfm_r    <- readRDS("data/processed/reddit_dfm.rds")
discursos <- readRDS("data/processed/discursos_paragraphs.rds")

# --- Migration keyword rate ---------------------------------------------------
mig <- dictionary(list(haiti = "hait*", extranjeros = "extranjer*",
                       inmigracion = c("inmigra*","inmigracion","inmigrantes"),
                       migracion   = c("migra*","migracion","migrantes"),
                       border = c("fronter*","muro"), deportation = "deport*",
                       refugee = "refugi*", illegal = c("ilegal*","indocumenta*")))
rate <- \(dfm, src) tibble(category = names(colSums(dfm_lookup(dfm, mig))),
                            count = colSums(dfm_lookup(dfm, mig)),
                            rate  = 1000 * count / sum(ntoken(dfm)), source = src)
freq <- bind_rows(rate(dfm_d, "Discourses"), rate(dfm_r, "Reddit"))
write_csv(freq, "output/tables/migration_keyword_frequency.csv")
save_fig(ggplot(freq, aes(reorder(category, rate), rate)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() + facet_wrap(~ source, scales = "free_x") +
  labs(title = "Migration vocabulary: rate per 1,000 tokens", x = NULL, y = NULL) +
  theme_minimal(), "01_migration_keyword_frequency.png")

write_csv(as_tibble(head(kwic(tokens(corpus_d), "hait*", 6), 50)), "output/tables/kwic_haiti_discursos.csv")
write_csv(as_tibble(head(kwic(tokens(corpus_r), "hait*", 6), 50)), "output/tables/kwic_haiti_reddit.csv")

# --- Optimal K diagnostic (Griffiths/CaoJuan/Arun/Deveaud) --------------------
# Inspect both PNGs and the k_sweep_* tibbles before choosing K per corpus.
sweep_k <- \(dfm, label) {
  r <- FindTopicsNumber(dfm, 2:10, c("Griffiths2004","CaoJuan2009","Arun2010","Deveaud2014"),
                        method = "Gibbs", control = list(seed = 1904), verbose = FALSE)
  png(file.path("output/figures/nlp", paste0("02_topicnumber_", label, ".png")),
      1200, 700, res = 150); FindTopicsNumber_plot(r); dev.off()
  r
}
k_sweep_d <- sweep_k(dfm_group(dfm_d, groups = docvars(corpus_d, "doc_id")), "discursos")
k_sweep_r <- sweep_k(dfm_r, "reddit")

K_DISCURSOS <- 6   # set after looking at k_sweep_d
K_REDDIT    <- 6   # set after looking at k_sweep_r

# --- Seeded LDA: 5 anchored topics + 1 residual -------------------------------
seeds <- dictionary(list(
  haiti_migration = c("haiti*","haitian*","migra*","inmigra*","frontera*","deport*","refugi*","muro"),
  security = c("seguridad","delincuen*","violenci*","crimen*","policia*","militar*","narco*"),
  economy  = c("econom*","trabaj*","empleo*","salari*","pobreza","inversion*","industri*","turism*"),
  health   = c("salud","hospital*","medic*","sanitar*","covid*","pandemi*"),
  identity = c("dominican*","patria","nacion*","cultura","raza","negro*","racis*")))

set.seed(1904)
slda_d <- textmodel_seededlda(dfm_subset(dfm_d, ntoken(dfm_d) > 0),
                              seeds, residual = TRUE, batch_size = 0.01)
slda_r <- textmodel_seededlda(dfm_subset(dfm_r, ntoken(dfm_r) > 0),
                              seeds, residual = TRUE, batch_size = 0.01)
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

# --- H2: migration framing in presidential discourse --------------------------
# Mean topic share across discourse paragraphs that contain a migration keyword.
# Expect: security + health > identity (framing as logistical/security issue).
flag_mig <- \(t) str_detect(tolower(t), "haiti|migra|inmigra|fronter|deport|refugi|indocumenta|muro|extranjer")
mig_ids <- as.character(discursos$paragraph_id[flag_mig(discursos$text)])
mig_theta <- slda_d$theta[rownames(slda_d$theta) %in% mig_ids, , drop = FALSE]
framing <- tibble(topic = colnames(mig_theta), mean_share = colMeans(mig_theta))
write_csv(framing, "output/tables/framing_migration_paragraphs.csv")
save_fig(ggplot(framing, aes(reorder(topic, mean_share), mean_share)) +
  geom_col(fill = ACC, width = 0.7) + coord_flip() +
  scale_y_continuous(labels = label_percent(1)) +
  labs(title = "How migration is framed in presidential discourse",
       subtitle = "Mean seeded-LDA topic share across paragraphs containing migration vocabulary",
       x = NULL, y = "Mean topic share") + theme_minimal(),
  "04_framing_migration.png")
