# ==============================================================================
# 01_data_collection.R
#
# Scrape presidential discourses from presidencia.gob.do and save them as
# PDFs under data/raw/discursos/. Skips PDFs that already exist locally so
# the script can be re-run incrementally.
#
# Output: data/raw/discursos/*.pdf, plus data/raw/discursos_index.csv with
# metadata (title, date, source URL) for the corpus we just downloaded.
# ==============================================================================

library(tidyverse)
library(rvest)

dir.create("data/raw/discursos", showWarnings = FALSE, recursive = TRUE)


# --- Step 1: Collect the list of discourses across all index pages ------------
# The presidencia.gob.do site paginates discourses. As of 2026 there are two
# pages — we collect both. If a future page appears, just extend the seq().

scrape_index_page <- function(page_num) {
  url   <- paste0("https://presidencia.gob.do/discursos?page=", page_num)
  page  <- read_html(url)
  nodes <- page |> html_elements("article")

  tibble(
    discourse = nodes |> html_element("h2 a") |> html_text(trim = TRUE),
    link      = nodes |> html_element("h2 a") |> html_attr("href"),
    datetime  = nodes |> html_element("time")  |> html_attr("datetime"),
    date_text = nodes |> html_element("time")  |> html_text(trim = TRUE)
  )
}

# Pages are 0 and 1; map_dfr binds them into one table.
df_index <- map_dfr(0:1, scrape_index_page) |>
  mutate(
    link     = str_c("https://presidencia.gob.do", link),
    datetime = as.POSIXct(datetime)
  ) |>
  # Build a clean, filesystem-safe id from the title.
  mutate(
    id   = str_to_lower(discourse) |>
      str_replace_all("[^a-z0-9 ]", "") |>
      str_squish() |>
      str_replace_all(" ", "_"),
    file = paste0("data/raw/discursos/", id, ".pdf")
  )


# --- Step 2: Resolve the real PDF URL from each discourse page ---------------
# The site wraps PDFs in a viewer iframe whose `src` contains the actual PDF
# URL as a percent-encoded `file=` query param.

resolve_pdf_url <- function(page_url) {
  page <- read_html(page_url)

  iframe_src <- page |> html_element("iframe") |> html_attr("src")
  if (is.na(iframe_src)) return(NA_character_)

  if (str_starts(iframe_src, "/")) {
    iframe_src <- paste0("https://presidencia.gob.do", iframe_src)
  }

  pdf_encoded <- str_extract(iframe_src, "(?<=file=).*")
  if (is.na(pdf_encoded)) return(NA_character_)

  url <- URLdecode(pdf_encoded)
  str_split(url, "#", simplify = TRUE)[1]  # drop #zoom=auto fragment
}


# --- Step 3: Download each PDF, skipping any that already exist --------------
walk2(
  df_index$link,
  df_index$file,
  \(page_url, dest) {
    if (file.exists(dest)) {
      message("skip (exists): ", basename(dest))
      return(invisible(NULL))
    }
    pdf_url <- try(resolve_pdf_url(page_url), silent = TRUE)
    if (inherits(pdf_url, "try-error") || is.na(pdf_url)) {
      message("could not resolve PDF for: ", page_url)
      return(invisible(NULL))
    }
    try(
      download.file(pdf_url, destfile = dest, mode = "wb", quiet = TRUE),
      silent = TRUE
    )
    Sys.sleep(2)  # polite delay between requests
  }
)


# --- Step 4: Persist the index for use by 02_preprocessing.R -----------------
write_csv(df_index, "data/raw/discursos_index.csv")

message("Done. ",
        sum(file.exists(df_index$file)), " / ", nrow(df_index),
        " PDFs present in data/raw/discursos/")
