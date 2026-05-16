# ==============================================================================
# 03_RD_descriptive_stats.R
#
# Descriptive plots for the migration report (Dominican Republic).
# All figures in English, single accent color, ggplot2 + theme_minimal.
#
# Inputs: data/raw/{detenidos_frontera,Naturalizaciones,arrestos}.csv
# Output: output/figures/descriptive_stats/*.png
# ==============================================================================

library(tidyverse)
library(scales)

dir.create("output/figures/descriptive_stats",
           showWarnings = FALSE, recursive = TRUE)

# Single accent color used everywhere
ACCENT <- "steelblue"

# Convenience saver — keep figure dimensions consistent across the report.
save_fig <- function(plot, name, w = 9, h = 5.5, dpi = 200) {
  path <- file.path("output/figures/descriptive_stats", name)
  ggsave(path, plot, width = w, height = h, dpi = dpi, bg = "white")
  message("saved: ", path)
}


# ==============================================================================
# 1. Border detentions (Haitians with irregular migratory status)
# ==============================================================================

frontera <- read_csv("data/raw/detenidos_frontera.csv", show_col_types = FALSE)

# 1a. Yearly total Haitian detentions ------------------------------------------
df_haitians_yr <- frontera |>
  filter(NACIONALIDAD == "Haitiano") |>
  group_by(year = ANO) |>
  summarise(count = sum(CANTIDAD, na.rm = TRUE), .groups = "drop")

p1 <- ggplot(df_haitians_yr, aes(x = factor(year), y = count)) +
  geom_col(fill = ACCENT, width = 0.7) +
  scale_y_continuous(labels = label_number(scale = 1e-3, suffix = "k")) +
  labs(
    title = "Haitians detained at the border with irregular migratory status",
    subtitle = "Annual totals, Dominican Republic",
    x = "Year",
    y = "Detentions",
    caption = "Source: Dirección General de Migración (DGM)"
  ) +
  theme_minimal(base_size = 12)

save_fig(p1, "01_haitians_detained_yearly.png")


# 1b. Monthly seasonality of detentions (all nationalities collapsed) ----------
spanish_months <- c("enero","febrero","marzo","abril","mayo","junio",
                    "julio","agosto","septiembre","octubre",
                    "noviembre","diciembre")
english_months <- c("Jan","Feb","Mar","Apr","May","Jun",
                    "Jul","Aug","Sep","Oct","Nov","Dec")

df_monthly <- frontera |>
  filter(NACIONALIDAD == "Haitiano") |>
  mutate(
    month_es = str_to_lower(MES),
    month_en = factor(english_months[match(month_es, spanish_months)],
                      levels = english_months)
  ) |>
  group_by(month_en) |>
  summarise(avg_count = mean(CANTIDAD, na.rm = TRUE), .groups = "drop")

p2 <- ggplot(df_monthly, aes(x = month_en, y = avg_count)) +
  geom_col(fill = ACCENT, width = 0.7) +
  scale_y_continuous(labels = label_number(scale = 1e-3, suffix = "k")) +
  labs(
    title = "Monthly seasonality of Haitian border detentions",
    subtitle = "Average detentions per month across 2018–2023",
    x = NULL,
    y = "Average detentions",
    caption = "Source: Dirección General de Migración (DGM)"
  ) +
  theme_minimal(base_size = 12)

save_fig(p2, "02_detentions_by_month.png")


# ==============================================================================
# 2. Naturalizations by country of origin
# ==============================================================================
# CSV is Latin-1 encoded (the column header "AÑO" mojibakes under UTF-8).

natz <- read.csv("data/raw/Naturalizaciones.csv",
                 fileEncoding = "Latin1", stringsAsFactors = FALSE) |>
  as_tibble() |>
  # Drop the trailing empty columns the source file leaves behind.
  select(PAIS, CANTIDAD, TRIMESTRE, AÑO) |>
  filter(!is.na(PAIS), PAIS != "")

# Translate country labels for the English version of the plot.
country_en <- c(
  "Colombia"       = "Colombia",
  "Cuba"           = "Cuba",
  "Venezuela"      = "Venezuela",
  "Italia"         = "Italy",
  "España"         = "Spain",
  "Haiti"          = "Haiti",
  "Francia"        = "France",
  "Estados Unidos" = "United States",
  "Rusia"          = "Russia",
  "China"          = "China",
  "Vietnam"        = "Vietnam",
  "Otros"          = "Other"
)

df_natz <- natz |>
  mutate(country = coalesce(country_en[PAIS], PAIS)) |>
  filter(country != "Other") |>
  group_by(country) |>
  summarise(total = sum(CANTIDAD, na.rm = TRUE), .groups = "drop") |>
  slice_max(total, n = 8)

p3 <- ggplot(df_natz, aes(x = total, y = reorder(country, total))) +
  geom_col(fill = ACCENT, width = 0.7) +
  labs(
    title = "Naturalizations granted by country of origin",
    subtitle = "Cumulative totals, 2018–2023 (Dominican Republic)",
    x = "Naturalizations granted",
    y = NULL,
    caption = "Source: Dirección General de Migración (DGM)"
  ) +
  theme_minimal(base_size = 12)

save_fig(p3, "03_naturalizations_by_country.png")


# ==============================================================================
# 3. Arrests by the National Police (2017–2023)
# ==============================================================================
# This CSV is also Latin-1 encoded and uses long format: one row per
# attribute (age band / sex / nationality) per quarter-year.

arr <- read.csv("data/raw/arrestos.csv",
                fileEncoding = "Latin1", stringsAsFactors = FALSE) |>
  as_tibble() |>
  rename(
    attribute = `Arrestados.segun.edad.sexo.y.nacionalidad`,
    count     = `Número.de.arrestos`,
    period    = Periodo,
    year      = Año
  )

# Bucket the long-format attribute column into three logical dimensions.
age_levels <- c("Edad 1 a 17","Edad 18 a 25","Edad 26 a 30","Edad 31 a 35",
                "Edad 36 a 40","Edad 41 a 45","Edad 46 a 50","Edad 51 a mas")
age_labels_en <- c("1–17","18–25","26–30","31–35",
                   "36–40","41–45","46–50","51+")

df_arr_age <- arr |>
  filter(attribute %in% age_levels) |>
  group_by(attribute) |>
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") |>
  mutate(age = factor(age_labels_en[match(attribute, age_levels)],
                      levels = age_labels_en))

df_arr_sex <- arr |>
  filter(attribute %in% c("Hombres", "Mujeres")) |>
  group_by(attribute) |>
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") |>
  mutate(sex = recode(attribute, "Hombres" = "Male", "Mujeres" = "Female"))

df_arr_nat <- arr |>
  filter(attribute %in% c("Dominicanos", "Extranjeros")) |>
  group_by(year, attribute) |>
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") |>
  mutate(nationality = recode(attribute,
                              "Dominicanos" = "Dominican",
                              "Extranjeros" = "Foreign"))


# 3a. Arrests by age band ------------------------------------------------------
p4 <- ggplot(df_arr_age, aes(x = age, y = count)) +
  geom_col(fill = ACCENT, width = 0.7) +
  scale_y_continuous(labels = label_number(scale = 1e-3, suffix = "k")) +
  labs(
    title = "Arrests by age band",
    subtitle = "Cumulative totals, January 2017 – July 2023",
    x = "Age band (years)",
    y = "Arrests",
    caption = "Source: Policía Nacional"
  ) +
  theme_minimal(base_size = 12)

save_fig(p4, "04_arrests_by_age.png")


# 3b. Arrests by sex -----------------------------------------------------------
p5 <- ggplot(df_arr_sex, aes(x = sex, y = count)) +
  geom_col(fill = ACCENT, width = 0.5) +
  scale_y_continuous(labels = label_number(scale = 1e-3, suffix = "k")) +
  labs(
    title = "Arrests by sex",
    subtitle = "Cumulative totals, January 2017 – July 2023",
    x = NULL,
    y = "Arrests",
    caption = "Source: Policía Nacional"
  ) +
  theme_minimal(base_size = 12)

save_fig(p5, "05_arrests_by_sex.png", w = 6, h = 5)


# 3c. Arrests by nationality — raw vs. population-adjusted --------------------
# Per ENI 2017, foreigners are 5.6% of the resident population. To compare
# arrest rates between groups we scale foreigner arrests by 100/5.6 ≈ 17.86.
FOREIGN_POP_SHARE <- 0.056
ADJ_FACTOR        <- (1 - FOREIGN_POP_SHARE) / FOREIGN_POP_SHARE  # ≈ 16.86

df_arr_nat_total <- df_arr_nat |>
  group_by(nationality) |>
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") |>
  mutate(
    adjusted = if_else(nationality == "Foreign",
                       count * ADJ_FACTOR, count)
  )

df_arr_nat_long <- df_arr_nat_total |>
  pivot_longer(c(count, adjusted),
               names_to = "view", values_to = "value") |>
  mutate(view = recode(view,
                       "count"    = "Raw counts",
                       "adjusted" = "Adjusted for population share"))

p6 <- ggplot(df_arr_nat_long,
             aes(x = nationality, y = value, fill = view)) +
  geom_col(position = "dodge", width = 0.6) +
  scale_fill_manual(values = c("Raw counts" = "grey75",
                               "Adjusted for population share" = ACCENT)) +
  scale_y_continuous(labels = label_number(scale = 1e-3, suffix = "k")) +
  labs(
    title = "Arrests by nationality: raw vs. population-adjusted",
    subtitle = paste0("Foreigners are 5.6% of residents (ENI 2017); ",
                      "their counts are scaled by ~17 for parity"),
    x = NULL,
    y = "Arrests",
    fill = NULL,
    caption = "Source: Policía Nacional; ENI 2017"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top")

save_fig(p6, "06_arrests_nationality_adjusted.png")


# 3d. Year-by-year adjusted ratio: Foreign / Dominican ------------------------
df_ratio <- df_arr_nat |>
  pivot_wider(names_from = nationality, values_from = count) |>
  mutate(
    foreign_adjusted = Foreign * ADJ_FACTOR,
    ratio = foreign_adjusted / Dominican
  )

p7 <- ggplot(df_ratio, aes(x = factor(year), y = ratio)) +
  geom_col(fill = ACCENT, width = 0.7) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey40") +
  scale_y_continuous(labels = label_number(accuracy = 0.1)) +
  labs(
    title = "Likelihood of arrest: foreigner vs. Dominican (population-adjusted)",
    subtitle = "Ratio > 1 means a foreigner is more likely to be arrested than a Dominican",
    x = "Year",
    y = "Adjusted arrest ratio (Foreign : Dominican)",
    caption = "Source: Policía Nacional; ENI 2017"
  ) +
  theme_minimal(base_size = 12)

save_fig(p7, "07_arrest_ratio_by_year.png")


message("Descriptive stats complete. Figures in ",
        "output/figures/descriptive_stats/")
