# 03_panel_regressions.R
#
# Purpose: Estimate the cross-state association between administrative burden
#          and SNAP participation using a state-year panel (2010-2019).
#
# Inputs:  data/intermediate/snap_annual_panel.rds
#
# Outputs: data/intermediate/regression_results.rds   (model objects)
#          output/tables/table2_ols_panel.csv          (export-ready table)
#          output/figures/fig_burden_participation.png (scatter + trend)
#
# Specifications:
#   M1: Pooled OLS  — no fixed effects (baseline / descriptive)
#   M2: State FE    — absorbs time-invariant state characteristics
#   M3: Year FE     — absorbs common national trends
#   M4: Two-way FE  — state + year FE (main specification)
#   M5: Two-way FE  — individual index components instead of composite
#
# Standard errors: clustered at the state level throughout.
#   51 clusters is on the small side. We flag this and later add a
#   wild cluster bootstrap robustness check (see script 03b).
#
# Outcome: log(persons_avg) — log of average monthly participants.
#   We do not have a true eligibility denominator, so we cannot compute
#   a proper take-up rate. State FE absorbs time-invariant size differences.
#   We discuss this limitation explicitly in the article.
#
# Causal interpretation: NONE claimed for M1-M4.
#   State policy is endogenous to state preferences for redistribution.
#   The two-way FE estimate is descriptive: within-state changes in burden
#   associated with within-state changes in participation, after removing
#   national year trends. We are honest about this throughout.

library(tidyverse)
library(fixest)

set.seed(42)

# ── 0. Paths ──────────────────────────────────────────────────────────────────

INTER_DIR  <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/data/intermediate"
TABLE_DIR  <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/output/tables"
FIGURE_DIR <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/output/figures"

# ── 1. Load and prepare data ──────────────────────────────────────────────────

panel <- readRDS(file.path(INTER_DIR, "snap_annual_panel.rds"))

# Add log outcome and numeric state id for fixest
panel <- panel |>
  mutate(
    log_persons = log(persons_avg),
    state_id    = as.integer(factor(state))
  )

message("Panel: ", nrow(panel), " rows | ",
        n_distinct(panel$state), " states | ",
        "Years: ", min(panel$year), "-", max(panel$year))

# Quick check: is there enough within-state variation in burden_index?
within_var <- panel |>
  group_by(state) |>
  summarise(sd_burden = sd(burden_index, na.rm = TRUE)) |>
  summarise(mean_within_sd = mean(sd_burden),
            min_within_sd  = min(sd_burden),
            max_within_sd  = max(sd_burden))

message("\nWithin-state SD of burden_index:")
message("  Mean: ", round(within_var$mean_within_sd, 4))
message("  Min : ", round(within_var$min_within_sd,  4))
message("  Max : ", round(within_var$max_within_sd,  4))
message("  (Near-zero min means some states never changed burden — fine.)")

# ── 2. Run regression models ──────────────────────────────────────────────────

# M1: Pooled OLS — no fixed effects
m1 <- feols(
  log_persons ~ burden_index,
  data    = panel,
  vcov    = ~state     # cluster at state
)

# M2: State FE only
m2 <- feols(
  log_persons ~ burden_index | state,
  data    = panel,
  vcov    = ~state
)

# M3: Year FE only
m3 <- feols(
  log_persons ~ burden_index | year,
  data    = panel,
  vcov    = ~state
)

# M4: Two-way FE — state + year (main specification)
m4 <- feols(
  log_persons ~ burden_index | state + year,
  data    = panel,
  vcov    = ~state
)

# M5: Two-way FE with individual components (unpacks the index)
m5 <- feols(
  log_persons ~ no_online_app + recert_burden + no_bbce + no_simplereport |
    state + year,
  data    = panel,
  vcov    = ~state
)

message("\n── Model summaries ────────────────────────────────")

models <- list(
  "M1 Pooled"      = m1,
  "M2 State FE"    = m2,
  "M3 Year FE"     = m3,
  "M4 Two-way FE"  = m4,
  "M5 Components"  = m5
)

for (nm in names(models)) {
  m   <- models[[nm]]
  cf  <- coef(m)
  se  <- se(m)
  # Print burden_index or first component coefficient
  var <- if ("burden_index" %in% names(cf)) "burden_index" else names(cf)[1]
  message(
    nm, ": coef = ", round(cf[var], 4),
    " | SE = ", round(se[var], 4),
    " | N = ", nobs(m)
  )
}

# ── 3. Coefficient table ──────────────────────────────────────────────────────
#
# Extract key statistics for Table 2 in the article.

extract_coef <- function(model, varname) {
  cf  <- coef(model)
  se  <- se(model)
  pv  <- pvalue(model)
  if (!varname %in% names(cf)) return(NULL)
  tibble(
    variable  = varname,
    coef      = cf[varname],
    std_error = se[varname],
    p_value   = pv[varname],
    stars     = case_when(
      pv[varname] < 0.01 ~ "***",
      pv[varname] < 0.05 ~ "**",
      pv[varname] < 0.10 ~ "*",
      TRUE               ~ ""
    ),
    n_obs     = nobs(model),
    r2_within = r2(model, type = "war")
  )
}

table2 <- bind_rows(
  extract_coef(m1, "burden_index") |> mutate(spec = "M1 Pooled OLS"),
  extract_coef(m2, "burden_index") |> mutate(spec = "M2 State FE"),
  extract_coef(m3, "burden_index") |> mutate(spec = "M3 Year FE"),
  extract_coef(m4, "burden_index") |> mutate(spec = "M4 Two-way FE"),
) |>
  select(spec, coef, std_error, stars, p_value, n_obs, r2_within)

message("\n── Table 2: Burden index coefficient ─────────────")
print(table2, n = 10)

# M5 individual components
table2_components <- bind_rows(
  extract_coef(m5, "no_online_app"),
  extract_coef(m5, "recert_burden"),
  extract_coef(m5, "no_bbce"),
  extract_coef(m5, "no_simplereport")
) |>
  mutate(spec = "M5 Components (two-way FE)") |>
  select(spec, variable, coef, std_error, stars, p_value, n_obs, r2_within)

message("\n── Table 2b: Individual components ───────────────")
print(table2_components, n = 10)

# Save tables
write_csv(table2,            file.path(TABLE_DIR, "table2_ols_panel.csv"))
write_csv(table2_components, file.path(TABLE_DIR, "table2b_components.csv"))

# ── 4. Diagnostic figure: within-state variation ──────────────────────────────
#
# Scatter of demeaned burden vs demeaned log participation.
# This is the variation M4 uses — shows what the two-way FE regression sees.

panel_demeaned <- panel |>
  group_by(state) |>
  mutate(
    burden_dm  = burden_index - mean(burden_index),
    persons_dm = log_persons  - mean(log_persons)
  ) |>
  ungroup() |>
  group_by(year) |>
  mutate(
    burden_dm  = burden_dm  - mean(burden_dm),
    persons_dm = persons_dm - mean(persons_dm)
  ) |>
  ungroup()

fig_scatter <- ggplot(panel_demeaned,
                      aes(x = burden_dm, y = persons_dm)) +
  geom_point(alpha = 0.35, size = 1.5, color = "#2c7bb6") +
  geom_smooth(method = "lm", se = TRUE, color = "#d7191c",
              linewidth = 0.9) +
  labs(
    title    = "Within-state variation: burden and log participation",
    subtitle = "State and year means removed (two-way demeaned)",
    x        = "Administrative burden index (demeaned)",
    y        = "Log monthly participants (demeaned)",
    caption  = "Each point is a state-year. OLS line from M4 specification."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold"),
    plot.subtitle = element_text(color = "gray40"),
    plot.caption  = element_text(color = "gray50", size = 9)
  )

ggsave(
  file.path(FIGURE_DIR, "fig_burden_participation.png"),
  fig_scatter,
  width = 7, height = 5, dpi = 300
)

message("\nFigure saved: fig_burden_participation.png")

# ── 5. Save model objects ─────────────────────────────────────────────────────

saveRDS(models, file.path(INTER_DIR, "regression_results.rds"))
message("Model objects saved: regression_results.rds")

message("\n── Done ─────────────────────────────────────────")
