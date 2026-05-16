# NLP sentiment analysis: Spanish RoBERTa via HuggingFace transformers
# (same pattern as the Day 5 UK prep script), per-keyword pos/neg bars,
# and upvote-weighted aggregation (H3) on Reddit migration content.
#
# Requires a Python environment with `transformers` installed and reachable
# from reticulate. Uncomment the use_condaenv() line if needed.

library(tidyverse); library(scales); library(reticulate); library(broom)

dir.create("output/figures/nlp", showWarnings = FALSE, recursive = TRUE)
dir.create("output/tables", showWarnings = FALSE, recursive = TRUE)
ACC <- "steelblue"
save_fig <- \(p, f, w = 10, h = 6) ggsave(file.path("output/figures/nlp", f),
                                          p, width = w, height = h, dpi = 200, bg = "white")

discursos <- readRDS("data/processed/discursos_paragraphs.rds")
red_sent  <- readRDS("data/processed/reddit_sentences.rds")

# --- Spanish sentiment transformer --------------------------------------------
# try(use_condaenv("textrpp_condaenv", required = TRUE), silent = TRUE)
transformers <- reticulate::import("transformers")
pipe <- transformers$pipeline("sentiment-analysis",
                              model = "pysentimiento/robertuito-sentiment-analysis",
                              device = -1L, top_k = NULL)

score_batched <- function(texts, batch_size = 64L) {
  out <- vector("list", length(texts))
  for (i in seq(1, length(texts), by = batch_size)) {
    j <- min(i + batch_size - 1L, length(texts))
    res <- pipe(as.list(texts[i:j]))
    for (k in seq_along(res)) {
      probs <- setNames(map_dbl(res[[k]], "score"), map_chr(res[[k]], "label"))
      out[[i + k - 1L]] <- tibble(p_pos = probs[["POS"]], p_neu = probs[["NEU"]],
                                  p_neg = probs[["NEG"]])
    }
  }
  bind_rows(out)
}

sent_d <- bind_cols(discursos["text"], score_batched(discursos$text)) |>
  mutate(neg = p_neg - p_pos, source = "Discourses (paragraphs)")
sent_r <- bind_cols(red_sent[c("text","upVotes","post_id")],
                    score_batched(red_sent$text)) |>
  mutate(neg = p_neg - p_pos, source = "Reddit (sentences)")
saveRDS(sent_d, "data/processed/sentiment_discursos.rds")
saveRDS(sent_r, "data/processed/sentiment_reddit.rds")

# --- H1 visual: negativity distribution for hait* sentences -------------------
save_fig(bind_rows(sent_d |> filter(str_detect(tolower(text), "hait")) |> select(neg, source),
                   sent_r |> filter(str_detect(tolower(text), "hait")) |> select(neg, source)) |>
  ggplot(aes(neg)) +
  geom_histogram(bins = 40, fill = ACC, color = "white", linewidth = 0.2) +
  facet_wrap(~ source, scales = "free_y") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  labs(title = "Negativity distribution of hait* sentences",
       subtitle = "neg = p(NEG) − p(POS) from Spanish RoBERTa sentiment",
       x = "Negativity score", y = "Count") + theme_minimal(),
  "05_negativity_haiti.png", w = 11, h = 5)

# --- Per-keyword POS vs NEG counts (Reddit sentences) -------------------------
kw <- list(`hait*` = "hait", extranjeros = "extranjer",
           `inmigr*` = "inmigra", `migr*` = "(?<![ie])migra")
kw_df <- imap_dfr(kw, \(re, name) sent_r |>
  filter(str_detect(tolower(text), re)) |>
  mutate(label = case_when(p_pos > p_neg & p_pos > p_neu ~ "Positive",
                           p_neg > p_pos & p_neg > p_neu ~ "Negative",
                           TRUE ~ "Neutral")) |>
  filter(label != "Neutral") |> count(label) |> mutate(keyword = name))

save_fig(ggplot(kw_df, aes(keyword, n, fill = label)) +
  geom_col(position = "dodge", width = 0.7) +
  scale_fill_manual(values = c(Positive = "grey70", Negative = ACC)) +
  labs(title = "Positive vs. negative Reddit sentences by migration keyword",
       x = NULL, y = "Sentences", fill = NULL) +
  theme_minimal() + theme(legend.position = "top"),
  "06_keyword_pos_neg.png")

# --- H3: upvote-weighted negativity + log1p(upvotes) regression ---------------
flag_mig <- \(t) str_detect(tolower(t), "haiti|migra|inmigra|fronter|deport|refugi|indocumenta|muro|extranjer")
mig_red <- sent_r |> filter(flag_mig(text))
w <- pmax(mig_red$upVotes, 1, na.rm = TRUE)

agg <- tibble(view = c("Unweighted mean", "Upvote-weighted mean"),
              value = c(mean(mig_red$neg, na.rm = TRUE),
                        weighted.mean(mig_red$neg, w, na.rm = TRUE)))
write_csv(agg, "output/tables/upvote_weighted_negativity.csv")

upvote_lm <- lm(neg ~ log1p(upVotes), data = mig_red)
write_csv(tidy(upvote_lm), "output/tables/upvote_regression.csv")

save_fig(ggplot(agg, aes(view, value)) +
  geom_col(fill = ACC, width = 0.6) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  labs(title = "Negativity of Reddit migration sentences: unweighted vs. upvote-weighted",
       subtitle = sprintf("OLS slope of neg on log1p(upvotes): %.3f (p = %.3f)",
                          coef(upvote_lm)[2], summary(upvote_lm)$coefficients[2, 4]),
       x = NULL, y = "Mean negativity score") + theme_minimal(),
  "07_upvote_weighting.png", w = 10, h = 5)
