# Scrape presidential discourses from presidencia.gob.do into data/raw/discursos/

library(tidyverse)
library(rvest)

dir.create("data/raw/discursos", showWarnings = FALSE, recursive = TRUE)

scrape_index <- function(page_num) {
  nodes <- read_html(paste0("https://presidencia.gob.do/discursos?page=", page_num)) |>
    html_elements("article")
  tibble(
    discourse = nodes |> html_element("h2 a") |> html_text(trim = TRUE),
    link      = nodes |> html_element("h2 a") |> html_attr("href"),
    datetime  = nodes |> html_element("time")  |> html_attr("datetime")
  )
}

df_index <- map_dfr(0:1, scrape_index) |>
  mutate(
    link     = str_c("https://presidencia.gob.do", link),
    datetime = as.POSIXct(datetime),
    id       = str_replace_all(str_to_lower(discourse), "[^a-z0-9 ]", "") |>
                 str_squish() |> str_replace_all(" ", "_"),
    file     = paste0("data/raw/discursos/", id, ".pdf")
  )

resolve_pdf <- function(page_url) {
  src <- read_html(page_url) |> html_element("iframe") |> html_attr("src")
  if (is.na(src)) return(NA_character_)
  if (str_starts(src, "/")) src <- paste0("https://presidencia.gob.do", src)
  URLdecode(str_extract(src, "(?<=file=).*")) |> str_split("#", simplify = TRUE) |> _[1]
}

walk2(df_index$link, df_index$file, \(u, f) {
  if (file.exists(f)) return(invisible())
  try(download.file(resolve_pdf(u), f, mode = "wb", quiet = TRUE), silent = TRUE)
  Sys.sleep(2)
})

write_csv(df_index, "data/raw/discursos_index.csv")
message(sum(file.exists(df_index$file)), " / ", nrow(df_index), " PDFs present")
