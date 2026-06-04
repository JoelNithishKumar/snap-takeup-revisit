# 01_build_participation_panel.R
#
# Purpose: Parse USDA SNAP FY participation files (FY10–FY23) and build a
#          clean state-month panel of persons participating in SNAP.
#
# Inputs:  C:/dev/PreDoc_Projects/snap-takeup-revisit/data/raw/
#            FY10.xls ... FY23.xls
#
# Outputs: C:/dev/PreDoc_Projects/snap-takeup-revisit/data/intermediate/
#            snap_participation_panel.rds
#            snap_participation_panel.csv
#
# Notes:
#   - Each FY file covers Oct(year-1) through Sep(year).
#     FY18 = Oct 2017 – Sep 2018.
#   - Seven regional sheets per file: NERO, MARO, SERO, MWRO, SWRO, MPRO, WRO.
#     US Summary sheet is skipped (regional aggregates only).
#   - Layout: rows 1–7 are title/header; row 8 onward alternates between
#     a state-name row (col1 = state name, col2–col6 empty) and 12 monthly
#     data rows, followed by a "Total" average row.
#   - Territories (Virgin Islands, Puerto Rico, Guam) and regional total
#     rows (NERO, MARO, …) are excluded.
#   - We extract the "Persons" column (column 3) as our participation outcome.

library(tidyverse)
library(readxl)

set.seed(42)  # not needed here but good habit for reproducible sessions

# ── 0. Paths ─────────────────────────────────────────────────────────────────

RAW_DIR   <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/data/raw"
INTER_DIR <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/data/intermediate"

# ── 1. Constants ──────────────────────────────────────────────────────────────

REGIONAL_SHEETS <- c("NERO", "MARO", "SERO", "MWRO", "SWRO", "MPRO", "WRO")

# Row values in col1 that are NOT state names — skip and reset current_state
SKIP_NAMES <- c(
  "NERO", "MARO", "SERO", "MWRO", "SWRO", "MPRO", "WRO",
  "Virgin Islands", "Puerto Rico", "Guam",
  "American Samoa", "Northern Mariana Islands",
  "Total"
)

# Two-digit fiscal year labels to process
FY_YEARS <- 10:23

# ── 2. Sheet parser ──────────────────────────────────────────────────────────
#
# Reads one regional sheet from one FY file.
# Returns a tibble with columns: state, date, persons.

parse_fy_sheet <- function(filepath, sheet_name) {

  # Read all cells as text; skip the 7-row title/header block.
  # col_types = "text" prevents readxl from coercing numeric months to dates.
  raw <- tryCatch(
    read_excel(
      filepath,
      sheet     = sheet_name,
      col_names = FALSE,
      skip      = 7,
      col_types = "text"
    ),
    error = function(e) NULL
  )

  if (is.null(raw) || nrow(raw) == 0) return(tibble())

  # Name the six columns by position
  names(raw) <- c("label", "households", "persons", "cost",
                  "cost_per_hh", "cost_per_person")

  current_state <- NA_character_
  results       <- vector("list", nrow(raw))
  n_results     <- 0L

  for (i in seq_len(nrow(raw))) {

    label <- str_trim(raw$label[[i]])
    pers  <- raw$persons[[i]]

    # Skip blank rows
    if (is.na(label) || label == "") next

    # Skip footnote lines
    if (str_starts(label, fixed("Footnote"))) next
    if (str_starts(label, "1."))             next

    # Detect state-name rows: label has text, persons cell is NA / empty
    if (is.na(pers) || str_trim(pers) == "") {
      if (label %in% SKIP_NAMES) {
        current_state <- NA_character_   # regional total block — ignore
      } else {
        current_state <- label           # genuine state name
      }
      next
    }

    # Skip "Total" average rows (label = "Total")
    if (label == "Total") next

    # Skip if we haven't identified a state yet
    if (is.na(current_state)) next

    # Parse date: label looks like "Oct 2017"
    parsed_date <- tryCatch(
      as.Date(paste("01", label), format = "%d %b %Y"),
      error = function(e) NA_Date_
    )
    if (is.na(parsed_date)) next

    # Parse persons (remove commas in case of formatted numbers)
    persons_num <- suppressWarnings(
      as.numeric(str_remove_all(pers, ","))
    )
    if (is.na(persons_num)) next

    n_results <- n_results + 1L
    results[[n_results]] <- tibble(
      state   = current_state,
      date    = parsed_date,
      persons = persons_num
    )
  }

  if (n_results == 0L) return(tibble())
  bind_rows(results[seq_len(n_results)])
}

# ── 3. Loop over fiscal years ─────────────────────────────────────────────────

all_data <- vector("list", length(FY_YEARS))

for (k in seq_along(FY_YEARS)) {

  yr       <- FY_YEARS[k]
  fy_label <- sprintf("FY%02d", yr)

  # Accept either .xls or .xlsx — newer FY files are .xlsx
  filepath_xls  <- file.path(RAW_DIR, paste0(fy_label, ".xls"))
  filepath_xlsx <- file.path(RAW_DIR, paste0(fy_label, ".xlsx"))

  if (file.exists(filepath_xls)) {
    filepath <- filepath_xls
  } else if (file.exists(filepath_xlsx)) {
    filepath <- filepath_xlsx
  } else {
    message("Not found — skipping: ", fy_label)
    next
  }

  message("Processing ", fy_label, " ...")

  fy_rows <- map_dfr(REGIONAL_SHEETS, function(sht) {
    rows <- parse_fy_sheet(filepath, sht)
    if (nrow(rows) > 0) rows else tibble()
  })

  message("  Rows: ", nrow(fy_rows),
          " | States: ", n_distinct(fy_rows$state))

  all_data[[k]] <- fy_rows
}

# ── 4. Stack, deduplicate, sort ───────────────────────────────────────────────

panel <- bind_rows(all_data) |>
  # Remove any duplicate state-month rows (defensive; should not occur)
  distinct(state, date, .keep_all = TRUE) |>
  arrange(state, date)

message("\n── Panel summary ──────────────────────────────────")
message("Total rows  : ", nrow(panel))
message("States      : ", n_distinct(panel$state))
message("Date range  : ", min(panel$date), " to ", max(panel$date))
message("Missing pers: ", sum(is.na(panel$persons)))

# ── 5. Save ───────────────────────────────────────────────────────────────────

saveRDS(panel, file.path(INTER_DIR, "snap_participation_panel.rds"))
write_csv(panel,  file.path(INTER_DIR, "snap_participation_panel.csv"))

message("\nSaved:")
message("  ", file.path(INTER_DIR, "snap_participation_panel.rds"))
message("  ", file.path(INTER_DIR, "snap_participation_panel.csv"))
