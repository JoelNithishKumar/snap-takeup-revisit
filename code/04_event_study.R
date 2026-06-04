# 04_event_study.R
#
# Purpose: Estimate the effect of the SNAP Emergency Allotment (EA) rollback
#          on monthly SNAP participation using a difference-in-differences
#          event study design.
#
# Background:
#   SNAP Emergency Allotments added a minimum of $95/month to every SNAP
#   household during COVID. The Consolidated Appropriations Act (Dec 29 2022)
#   terminated EA after the February 2023 issuance. 33 states + DC kept EA
#   through February 2023 and received the March 2023 benefit cut.
#   18 states had already opted out earlier (between 2021 and early 2023)
#   and are our comparison group.
#
# Design:
#   Treatment: states that kept EA through February 2023 (received March cut)
#   Control:   18 early opt-out states (already at normal benefits by March 2023)
#   Outcome:   log(persons) participating in SNAP, monthly
#   Event time: calendar month relative to March 2023
#   Pre-window: 12 months (March 2022 - February 2023)
#   Post-window: 6 months (March 2023 - August 2023, within our data)
#   FE: state + calendar month-year
#   SE: clustered at state
#
# Identification assumption (parallel trends):
#   In the absence of the March 2023 EA end, treatment and control states
#   would have followed parallel participation trajectories. We test this
#   by checking pre-trend coefficients. We discuss the selection threat:
#   early opt-out states skew Republican and lower-burden, which may
#   create diverging trends independent of EA.
#
# Inputs:  data/intermediate/snap_participation_panel.rds
# Outputs: output/figures/fig_event_study.png
#          output/figures/fig_pretrends.png
#          output/tables/table3_event_study.csv
#          data/intermediate/event_study_results.rds

library(tidyverse)
library(fixest)

set.seed(42)

# ── 0. Paths ──────────────────────────────────────────────────────────────────

INTER_DIR  <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/data/intermediate"
TABLE_DIR  <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/output/tables"
FIGURE_DIR <- "C:/dev/PreDoc_Projects/snap-takeup-revisit/output/figures"

# ── 1. Define treatment and control groups ────────────────────────────────────
#
# Early opt-out states: ended EA before March 2023.
# Source: USDA FNS (February 2023 blog post confirming 18 states had already
# ended EA). Precise opt-out months for 2021 states confirmed from Steffen &
# Kim (2024, Health Affairs Scholar); 2022 states are approximate and flagged.
# NOTE: verify 2022 exact months against FNS state waiver records before
# finalizing the article.

early_optout <- c(
  "Alaska",         # 2022 (approximate)
  "Arizona",        # 2022 (approximate)
  "Arkansas",       # 2021 (approximate)
  "Florida",        # 2021 (approximate)
  "Georgia",        # 2022 (approximate)
  "Idaho",          # March 2021 (confirmed: Steffen & Kim 2024)
  "Indiana",        # 2022 (approximate)
  "Iowa",           # 2022 (approximate)
  "Kentucky",       # 2022 (approximate)
  "Mississippi",    # 2021 (approximate)
  "Missouri",       # 2021 (approximate)
  "Montana",        # 2021 (approximate)
  "Nebraska",       # 2021 (approximate)
  "North Dakota",   # May 2021 (confirmed: Steffen & Kim 2024)
  "South Carolina", # August 2021 (confirmed: SCDSS press release)
  "South Dakota",   # 2021 (approximate)
  "Tennessee",      # 2021 (approximate)
  "Wyoming"         # 2022 (approximate)
)

# ── 2. Load and prepare monthly participation panel ───────────────────────────

part <- readRDS(file.path(INTER_DIR, "snap_participation_panel.rds"))

event_panel <- part |>
  filter(
    date >= as.Date("2022-03-01"),
    date <= as.Date("2023-08-01")
  ) |>
  mutate(
    log_persons = log(persons),
    event_time  = as.integer(
      round((as.numeric(date) - as.numeric(as.Date("2023-03-01"))) / 30.44)
    ),
    treated    = if_else(state %in% early_optout, 0L, 1L),
    month_year = format(date, "%Y-%m")
  )

message("Event panel: ", nrow(event_panel), " rows")
message("  Date range  : ", min(event_panel$date), " to ", max(event_panel$date))
message("  Treated states (March 2023 cut): ",
        n_distinct(event_panel$state[event_panel$treated == 1]))
message("  Control states (early opt-out)  : ",
        n_distinct(event_panel$state[event_panel$treated == 0]))
message("  Event time range: ", min(event_panel$event_time),
        " to ", max(event_panel$event_time))

# ── 3. Pre-trends figure ──────────────────────────────────────────────────────

pre_trends <- event_panel |>
  group_by(treated, date) |>
  summarise(
    mean_log_persons = mean(log_persons, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    group = if_else(
      treated == 1,
      "Treatment (EA through Feb 2023)",
      "Control (early opt-out)"
    )
  )

fig_pretrends <- ggplot(
  pre_trends,
  aes(x = date, y = mean_log_persons, color = group, linetype = group)
) +
  geom_line(linewidth = 0.9) +
  geom_vline(
    xintercept = as.Date("2023-03-01"),
    linetype = "dashed", color = "gray40"
  ) +
  annotate(
    "text", x = as.Date("2023-02-15"), y = Inf,
    label = "EA ends\nMarch 2023", vjust = -0.3, hjust = 1,
    size = 3.5, color = "gray40"
  ) +
  scale_color_manual(
    values = c(
      "Control (early opt-out)"         = "#2c7bb6",
      "Treatment (EA through Feb 2023)" = "#d7191c"
    )
  ) +
  scale_linetype_manual(
    values = c(
      "Control (early opt-out)"         = "dashed",
      "Treatment (EA through Feb 2023)" = "solid"
    )
  ) +
  labs(
    title    = "Mean log SNAP participation: treatment vs. control states",
    subtitle = "Treatment = kept EA through February 2023 | Control = early opt-out",
    x        = NULL,
    y        = "Mean log(monthly participants)",
    color    = NULL,
    linetype = NULL,
    caption  = "Vertical dashed line: March 2023 (EA ends for treatment states)."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position  = "bottom",
    plot.title       = element_text(face = "bold"),
    plot.subtitle    = element_text(color = "gray40"),
    plot.caption     = element_text(color = "gray50", size = 9),
    panel.background = element_rect(fill = "white", color = NA),
    plot.background  = element_rect(fill = "white", color = NA)
  )

ggsave(
  file.path(FIGURE_DIR, "fig_pretrends.png"),
  fig_pretrends, width = 8, height = 5, dpi = 300
)
message("Pre-trends figure saved.")

# ── 4. Event study regression ─────────────────────────────────────────────────

es_model <- feols(
  log_persons ~ i(event_time, treated, ref = -1) | state + month_year,
  data = event_panel,
  vcov = ~state
)

message("\nEvent study model estimated. N = ", nobs(es_model))

# ── 5. Extract coefficients ───────────────────────────────────────────────────

es_coefs <- as.data.frame(coeftable(es_model)) |>
  rownames_to_column("term") |>
  filter(str_starts(term, "event_time::")) |>
  mutate(
    event_time = as.integer(str_extract(term, "-?\\d+")),
    coef       = Estimate,
    se         = `Std. Error`,
    ci_lo      = coef - 1.96 * se,
    ci_hi      = coef + 1.96 * se
  ) |>
  select(event_time, coef, se, ci_lo, ci_hi) |>
  bind_rows(
    data.frame(event_time = -1L, coef = 0, se = 0, ci_lo = 0, ci_hi = 0)
  ) |>
  arrange(event_time)

message("\nEvent-study coefficients:")
print(as.data.frame(es_coefs))

# ── 6. Event study figure ─────────────────────────────────────────────────────

fig_es <- ggplot(es_coefs, aes(x = event_time, y = coef)) +
  geom_hline(yintercept = 0, color = "gray60", linewidth = 0.5) +
  geom_vline(
    xintercept = -0.5, linetype = "dashed",
    color = "gray40", linewidth = 0.6
  ) +
  annotate(
    "text", x = -0.5, y = Inf,
    label = "EA ends", vjust = -0.5, hjust = 1,
    size = 3.5, color = "gray40"
  ) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, fill = "#2c7bb6") +
  geom_line(color = "#2c7bb6", linewidth = 0.9) +
  geom_point(color = "#2c7bb6", size = 2.5) +
  scale_x_continuous(
    breaks = min(es_coefs$event_time):max(es_coefs$event_time),
    labels = function(x) paste0(ifelse(x >= 0, "+", ""), x)
  ) +
  labs(
    title    = "Event study: EA rollback and SNAP participation",
    subtitle = "Treated x event-time coefficients | Reference = month -1 (Feb 2023)",
    x        = "Months relative to March 2023 EA end",
    y        = "Difference in log participants\n(treated vs. control)",
    caption  = paste0(
      "State + month-year FEs. SE clustered at state (51 clusters).\n",
      "95% CI shown. Reference: February 2023 (event time -1)."
    )
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold"),
    plot.subtitle    = element_text(color = "gray40"),
    plot.caption     = element_text(color = "gray50", size = 9),
    panel.background = element_rect(fill = "white", color = NA),
    plot.background  = element_rect(fill = "white", color = NA)
  )

ggsave(
  file.path(FIGURE_DIR, "fig_event_study.png"),
  fig_es, width = 8, height = 5, dpi = 300
)
message("Event study figure saved.")

# ── 7. Pre-trend diagnostics ──────────────────────────────────────────────────

message("\nPre-trend coefficients (event_time < -1):")
pre_coefs <- es_coefs |> filter(event_time < -1)
print(as.data.frame(pre_coefs))

message("\nMax absolute pre-trend coef : ",
        round(max(abs(pre_coefs$coef), na.rm = TRUE), 4))
message("Pre-trend coefs all within 95% CI of zero: ",
        all(pre_coefs$ci_lo <= 0 & pre_coefs$ci_hi >= 0, na.rm = TRUE))

# ── 8. Save ───────────────────────────────────────────────────────────────────

write_csv(es_coefs, file.path(TABLE_DIR, "table3_event_study.csv"))
saveRDS(es_model,   file.path(INTER_DIR, "event_study_results.rds"))

message("\nSaved:")
message("  output/figures/fig_event_study.png")
message("  output/figures/fig_pretrends.png")
message("  output/tables/table3_event_study.csv")
message("  data/intermediate/event_study_results.rds")
message("\n── Done ─────────────────────────────────────────")