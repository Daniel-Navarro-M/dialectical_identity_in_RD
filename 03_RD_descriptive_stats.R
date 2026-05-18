# Migration descriptive plots — English, single accent color.
# Each plot is built as an object (p1..p7), previewed, then saved with ggsave.

rm(list = ls())

library(tidyverse); library(scales)

dir.create("output/figures/descriptive_stats", showWarnings = FALSE, recursive = TRUE)

ACC <- "steelblue"
OUT <- "output/figures/descriptive_stats"

# Plot theme — tweak any element below; it applies to every plot in the script.
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

kfmt <- scale_y_continuous(labels = label_number(scale = 1e-3, suffix = "k"))

# --- Border detentions (Haitians) ---------------------------------------------
frontera <- read_csv("data/raw/detenidos_frontera.csv", show_col_types = FALSE) |>
  filter(NACIONALIDAD == "Haitiano")

p1 <- frontera |>
  group_by(year = ANO) |>
  summarise(n = sum(CANTIDAD), .groups = "drop") |>
  ggplot(aes(factor(year), n)) +
  geom_col(fill = ACC, width = 0.7) + kfmt +
  labs(title = "Haitians detained at the border with irregular migratory status",
       x = "Year", y = "Detentions",
       caption = "Source: DGM") +
  THEME

ggsave(file.path(OUT, "01_haitians_detained_yearly.png"), p1,
       width = 9, height = 5.5, dpi = 200, bg = "white")

months_es <- c("enero","febrero","marzo","abril","mayo","junio",
               "julio","agosto","septiembre","octubre","noviembre","diciembre")
months_en <- c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")

p2 <- frontera |>
  mutate(m = factor(months_en[match(str_to_lower(MES), months_es)], levels = months_en)) |>
  group_by(m) |>
  summarise(avg = mean(CANTIDAD), .groups = "drop") |>
  ggplot(aes(m, avg)) +
  geom_col(fill = ACC, width = 0.7) + kfmt +
  labs(title = "Monthly seasonality of Haitian border detentions",
       x = NULL, y = "Average detentions", caption = "Source: DGM") +
  THEME

ggsave(file.path(OUT, "02_detentions_by_month.png"), p2,
       width = 9, height = 5.5, dpi = 200, bg = "white")

# --- Naturalizations ----------------------------------------------------------
country_en <- c(Colombia="Colombia", Cuba="Cuba", Venezuela="Venezuela", Italia="Italy",
                España="Spain", Haiti="Haiti", Francia="France",
                `Estados Unidos`="United States", Rusia="Russia", China="China",
                Vietnam="Vietnam", Otros="Other")

p3 <- read.csv("data/raw/Naturalizaciones.csv", fileEncoding = "Latin1") |>
  as_tibble() |>
  filter(!is.na(PAIS), PAIS != "", PAIS != "Otros") |>
  mutate(country = coalesce(country_en[PAIS], PAIS)) |>
  group_by(country) |>
  summarise(n = sum(CANTIDAD), .groups = "drop") |>
  slice_max(n, n = 8) |>
  ggplot(aes(n, reorder(country, n))) +
  geom_col(fill = ACC, width = 0.7) +
  labs(title = "Naturalizations granted by country of origin (2018–2023)",
       x = "Naturalizations", y = NULL, caption = "Source: DGM") +
  THEME

ggsave(file.path(OUT, "03_naturalizations_by_country.png"), p3,
       width = 9, height = 5.5, dpi = 200, bg = "white")

# --- Arrests ------------------------------------------------------------------
arr <- read.csv("data/raw/arrestos.csv", fileEncoding = "Latin1") |>
  as_tibble() |>
  rename(attr = 1, n = 2, period = 3, year = 4)

ages_es <- paste0("Edad ", c("1 a 17","18 a 25","26 a 30","31 a 35",
                             "36 a 40","41 a 45","46 a 50","51 a mas"))
ages_en <- c("1–17","18–25","26–30","31–35","36–40","41–45","46–50","51+")

p4 <- arr |>
  filter(attr %in% ages_es) |>
  group_by(age = factor(ages_en[match(attr, ages_es)], levels = ages_en)) |>
  summarise(n = sum(n), .groups = "drop") |>
  ggplot(aes(age, n)) +
  geom_col(fill = ACC, width = 0.7) + kfmt +
  labs(title = "Arrests by age band (2017–2023)",
       x = "Age band", y = "Arrests",
       caption = "Source: Policía Nacional") +
  THEME

ggsave(file.path(OUT, "04_arrests_by_age.png"), p4,
       width = 9, height = 5.5, dpi = 200, bg = "white")

p5 <- arr |>
  filter(attr %in% c("Hombres","Mujeres")) |>
  group_by(sex = recode(attr, Hombres = "Male", Mujeres = "Female")) |>
  summarise(n = sum(n), .groups = "drop") |>
  ggplot(aes(sex, n)) +
  geom_col(fill = ACC, width = 0.5) + kfmt +
  labs(title = "Arrests by sex (2017–2023)", x = NULL, y = "Arrests",
       caption = "Source: Policía Nacional") +
  THEME

ggsave(file.path(OUT, "05_arrests_by_sex.png"), p5,
       width = 9, height = 5.5, dpi = 200, bg = "white")

# Population adjustment: foreigners are 5.6% of residents (ENI 2017)
ADJ <- (1 - 0.056) / 0.056

nat <- arr |>
  filter(attr %in% c("Dominicanos","Extranjeros")) |>
  group_by(year, nat = recode(attr, Dominicanos = "Dominican", Extranjeros = "Foreign")) |>
  summarise(n = sum(n), .groups = "drop")

p6 <- nat |>
  group_by(nat) |>
  summarise(n = sum(n), .groups = "drop") |>
  mutate(adjusted = if_else(nat == "Foreign", n * ADJ, n)) |>
  pivot_longer(c(n, adjusted), names_to = "view") |>
  mutate(view = recode(view, n = "Raw counts", adjusted = "Population-adjusted")) |>
  ggplot(aes(nat, value, fill = view)) +
  geom_col(position = "dodge", width = 0.6) +
  scale_fill_manual(values = c(`Raw counts` = "grey75", `Population-adjusted` = ACC)) +
  kfmt +
  labs(title = "Arrests by nationality: raw vs. population-adjusted",
       x = NULL, y = "Arrests", fill = NULL,
       caption = "Foreigners = 5.6% of residents (ENI 2017). Source: Policía Nacional") +
  THEME

ggsave(file.path(OUT, "06_arrests_nationality_adjusted.png"), p6,
       width = 9, height = 5.5, dpi = 200, bg = "white")

p7 <- nat |>
  pivot_wider(names_from = nat, values_from = n) |>
  mutate(ratio = (Foreign * ADJ) / Dominican) |>
  ggplot(aes(factor(year), ratio)) +
  geom_col(fill = ACC, width = 0.7) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey40") +
  labs(title = "Likelihood of arrest: foreigner vs. Dominican (adjusted)",
       subtitle = "Ratio > 1 foreigner more likely to be arrested",
       x = "Year", y = "Adjusted ratio (Foreign : Dominican)") +
  THEME

ggsave(file.path(OUT, "07_arrest_ratio_by_year.png"), p7,
       width = 9, height = 5.5, dpi = 200, bg = "white")
