# 02_build_burden_index.R
#
# Purpose: Import the ERS SNAP Policy Database, construct a composite
#          administrative-burden index, aggregate monthly data to
#          calendar-year level, and merge with the participation panel
#          from script 01.
#
# Inputs:  data/raw/SNAPPolicyDatabase.xlsx
#          data/intermediate/snap_participation_panel.rds
#
# Outputs: data/intermediate/snap_annual_panel.rds
#          data/intermediate/snap_annual_panel.csv
#
# Burden index construction:
#   We use four components where 1 = more burden, 0 = less burden.
#   Higher burden_index = more administrative friction.
#
#   (1) no_online_app  : 1 if state has no statewide online application
#                        (oapp == 0); 0 if oapp >= 1.
#                        Missing from March 2020 onward — fine for 2010-2018.
#
#   (2) short_recert   : Standardized INVERSE of certnonearnavg.
#                        Longer recertification period = less frequent
#                        recertification = LESS burden. We flip the sign
#                        so that a higher value still means more burden.
#                        Missing from Oct 2019 — we cap OLS panel at 2018.
#
#   (3) no_bbce        : 1 if state has no broad-based categorical eligibility
#                        (bbce == 0); 0 if bbce == 1.
#                        BBCE loosens asset and income tests = less burden.
#
#   (4) no_simplereport: 1 if state does not use simplified reporting for
#                        earners (reportsimple == 0); 0 if reportsimple == 1.
#
#   burden_index = mean of non-missing components, so it always lies in [0,1]
#                  regardless of how many components are available.
#
# Note on faceini / facerec (face-to-face interview waivers):
#   These are missing from Jan 2017 onward in the policy database.
#   Including them would restrict the panel to 2010-2016.
#   We omit them from the main index and discuss this as a limitation.
#   A robustness check using 2010-2016 only with all five components
#   is flagged as a TODO.

library(tidyverse)
library(readxl)

set.seed(42)

# ── 0. Paths ──────────────────────────────────────────────────────────────────

RAW_DIR   <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/data/raw"
INTER_DIR <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/data/intermediate"

# ── 1. Import Policy Database ─────────────────────────────────────────────────

message("Reading SNAP Policy Database ...")

policy_raw <- read_excel(
  file.path(RAW_DIR, "SNAPPolicyDatabase.xlsx"),
  sheet     = "SNAP Policy Database",
  col_types = "text"   # read as text; coerce manually below
)

message("  Raw rows: ", nrow(policy_raw), " | Cols: ", ncol(policy_raw))

# ── 2. Select and coerce variables ────────────────────────────────────────────

policy <- policy_raw |>
  select(
    state_fips   = state_fips,
    statename    = statename,
    yearmonth    = yearmonth,   # YYYYMM integer
    bbce         = bbce,
    certnonearnavg = certnonearnavg,
    oapp         = oapp,
    reportsimple = reportsimple,
    faceini      = faceini,
    facerec      = facerec
  ) |>
  mutate(
    across(c(state_fips, yearmonth, bbce, oapp, reportsimple,
             faceini, facerec), as.integer),
    certnonearnavg = as.numeric(certnonearnavg),
    # Parse yearmonth (YYYYMM) → first-of-month date
    year  = as.integer(yearmonth %/% 100),
    month = as.integer(yearmonth %%  100),
    date  = as.Date(sprintf("%04d-%02d-01", year, month))
  ) |>
  # Restrict to 2010-2019 — our OLS panel window
  filter(year >= 2010, year <= 2019) |>
  # Drop territories (state_fips > 56 or known non-state codes)
  filter(state_fips <= 56)

message("  After filter (2010-2019, states only): ", nrow(policy), " rows")
message("  States: ", n_distinct(policy$statename))

# ── 3. Build burden index components ─────────────────────────────────────────
#
# Each component is coded 1 = more burden, 0 = less burden.

policy <- policy |>
  mutate(
    # (1) No statewide online application
    no_online_app   = if_else(oapp == 0, 1L, 0L, missing = NA_integer_),

    # (2) Short recertification period (inverse of certnonearnavg, standardized)
    #     We use -certnonearnavg so that shorter periods → higher burden.
    #     Standardize to [0,1] range within sample using min-max scaling.
    recert_burden_raw = -certnonearnavg,

    # (3) No broad-based categorical eligibility
    no_bbce         = if_else(bbce == 0, 1L, 0L, missing = NA_integer_),

    # (4) No simplified reporting
    no_simplereport = if_else(reportsimple == 0, 1L, 0L, missing = NA_integer_)
  )

# Min-max scale recert_burden_raw to [0,1] within the full sample
policy <- policy |>
  mutate(
    recert_burden = (recert_burden_raw - min(recert_burden_raw, na.rm = TRUE)) /
      (max(recert_burden_raw, na.rm = TRUE) - min(recert_burden_raw, na.rm = TRUE))
  )

# Composite index: row-mean of non-missing components → always in [0,1]
policy <- policy |>
  mutate(
    burden_index = rowMeans(
      cbind(no_online_app, recert_burden, no_bbce, no_simplereport),
      na.rm = TRUE
    )
  )

# ── 4. Aggregate to calendar year ────────────────────────────────────────────
#
# Take annual mean of monthly values within each state-year.
# This smooths over mid-year policy changes and aligns with the
# annual participation aggregates we build below.

policy_annual <- policy |>
  group_by(statename, state_fips, year) |>
  summarise(
    burden_index    = mean(burden_index,    na.rm = TRUE),
    no_online_app   = mean(no_online_app,   na.rm = TRUE),
    recert_burden   = mean(recert_burden,   na.rm = TRUE),
    no_bbce         = mean(no_bbce,         na.rm = TRUE),
    no_simplereport = mean(no_simplereport, na.rm = TRUE),
    certnonearnavg  = mean(certnonearnavg,  na.rm = TRUE),
    bbce            = mean(bbce,            na.rm = TRUE),
    oapp_mean       = mean(oapp,            na.rm = TRUE),
    .groups = "drop"
  )

message("\nPolicy annual panel: ", nrow(policy_annual), " state-year rows")

# ── 5. Aggregate participation to calendar year ───────────────────────────────
#
# The FY files give us Oct(y-1)–Sep(y) months.
# We aggregate to calendar year (Jan–Dec) by extracting year from date.

part <- readRDS(file.path(INTER_DIR, "snap_participation_panel.rds"))

part_annual <- part |>
  mutate(year = as.integer(format(date, "%Y"))) |>
  filter(year >= 2010, year <= 2019) |>
  group_by(state, year) |>
  summarise(
    persons_avg = mean(persons, na.rm = TRUE),   # avg monthly participants
    persons_max = max(persons,  na.rm = TRUE),   # peak-month participants
    n_months    = n(),
    .groups = "drop"
  )

message("Participation annual panel: ", nrow(part_annual), " state-year rows")
message("  States: ", n_distinct(part_annual$state))

# ── 6. Merge ──────────────────────────────────────────────────────────────────
#
# Join on state name. Check for mismatches before merging.

# Standardize name field for join
policy_annual <- policy_annual |> rename(state = statename)

unmatched_part   <- setdiff(unique(part_annual$state),   unique(policy_annual$state))
unmatched_policy <- setdiff(unique(policy_annual$state), unique(part_annual$state))

if (length(unmatched_part) > 0) {
  message("WARNING — In participation but not policy: ",
          paste(unmatched_part, collapse = ", "))
}
if (length(unmatched_policy) > 0) {
  message("WARNING — In policy but not participation: ",
          paste(unmatched_policy, collapse = ", "))
}

panel <- inner_join(part_annual, policy_annual, by = c("state", "year"))

message("\n── Merged panel summary ───────────────────────────")
message("Total rows  : ", nrow(panel))
message("States      : ", n_distinct(panel$state))
message("Years       : ", min(panel$year), " – ", max(panel$year))
message("Missing burden_index: ", sum(is.na(panel$burden_index)))
message("Missing persons_avg : ", sum(is.na(panel$persons_avg)))

# Quick summary of burden index distribution
message("\nBurden index distribution:")
print(summary(panel$burden_index))

# ── 7. Save ───────────────────────────────────────────────────────────────────

saveRDS(panel, file.path(INTER_DIR, "snap_annual_panel.rds"))
write_csv(panel, file.path(INTER_DIR, "snap_annual_panel.csv"))

message("\nSaved:")
message("  ", file.path(INTER_DIR, "snap_annual_panel.rds"))
message("  ", file.path(INTER_DIR, "snap_annual_panel.csv"))
