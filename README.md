# Administrative Burden and SNAP Participation: A State-Panel Analysis with Evidence from the Emergency Allotment Rollback

**Joel Nithish Kumar Murugan** 

---

## Overview

SNAP the Supplemental Nutrition Assistance Program is a federal entitlement. If your household income falls below 130 percent of the federal poverty line, you are legally eligible. The money is appropriated. There is no waitlist. And yet in 2023, the Program Access Index ranged from 0.36 in Wyoming to 1.32 in the District of Columbia. A gap that large, between states administering the same federal program to the same eligibility standard, demands an explanation.

This project investigates one candidate: administrative burden. States make different choices about how burdensome they make the process of applying for and keeping SNAP benefits whether they offer online applications, how frequently they require recertification, whether they adopt simplified reporting for working households. This repository builds a composite burden index from four policy variables, estimates its association with participation across a decade of state-level data, and uses the staggered rollback of pandemic-era Emergency Allotments in 2022 and 2023 as a quasi-experiment to test whether a large, sudden policy change produced a detectable change in enrollment.

---

## Key Findings

**Cross-sectional association is large.** Moving from the lowest to the highest burden state is associated with participation roughly 2.4 percent lower, a result that holds across multiple specifications and is statistically significant at the one percent level.

**Within-state estimate shrinks to near zero.** After absorbing stable state differences and national year trends with two-way fixed effects, the coefficient on the burden index falls to −0.046 and is statistically indistinguishable from zero. This is consistent with state-level selection  states that design high-burden programs tend to be states with structurally lower participation for reasons beyond the paperwork.

**Simplified reporting is the most robust signal.** Of the four burden components, only the absence of simplified reporting for earners survives the two-way fixed effects test, showing participation 12 percent lower in states without it (p-value = 0.018). This points to compliance costs for working households as a specific, actionable policy lever.

**The EA rollback did not reduce headcount.** A difference-in-differences event study around the March 2023 federal end of Emergency Allotments finds no statistically significant decline in SNAP participation in states that received the benefit cut, relative to the 18 states that had already ended Emergency Allotments earlier. Post-period coefficients range from −0.015 to −0.030 and all confidence intervals include zero.

---

## Data Sources

| Dataset | Source | Coverage |
|---|---|---|
| SNAP state participation files | USDA Food and Nutrition Service | Monthly, state-level, FY2010–FY2023 |
| SNAP Policy Database | USDA Economic Research Service | Monthly, state-level, 1996–2020 |
| Program Access Index | USDA Food and Nutrition Service | Annual, state-level, 2022–2023 |

All data files are publicly available and freely downloadable from the URLs listed in the paper. Raw files are included in this repository for convenience but should be re-downloaded from source to ensure the most current versions.

---

## Repository Structure

```
snap-takeup-revisit/
├── code/
│   ├── 01_build_participation_panel.R   # Parse FY files → state-month panel
│   ├── 02_build_burden_index.R          # Build burden index, merge panels
│   ├── 03_panel_regressions.R           # OLS panel regressions, Table 2
│   └── 04_event_study.R                 # DiD event study, Table 3
├── data/
│   ├── raw/                             # Original files, unmodified
│   └── intermediate/                    # Cleaned panels produced by scripts
├── output/
│   ├── figures/                         # All figures referenced in paper
│   └── tables/                          # All tables referenced in paper
└── writing/
    └── article.md                       # Full paper
```

---

## Reproducing the Analysis

**Requirements:** R version 4.4.2 or later. Install required packages once:

```r
install.packages(c("tidyverse", "fixest", "readxl", "sf"))
```

**Run scripts in order:**

```r
source("code/01_build_participation_panel.R")
source("code/02_build_burden_index.R")
source("code/03_panel_regressions.R")
source("code/04_event_study.R")
```

Each script reads from the previous script's saved outputs. No script modifies a raw data file. Total runtime is approximately five minutes on a standard laptop.

---

## Limitations

This analysis uses publicly available aggregate data  state-year averages of participation counts and policy indicators. It cannot observe individual applications, denials, or churn. The two-way fixed effects estimate being near zero is a limitation of the research design, not a definitive claim that administrative burden has no effect. The event study parallel trends assumption is imperfect: early opt-out states skew Republican and are structurally different from states that kept Emergency Allotments through February 2023. Precise monthly Emergency Allotment opt-out dates for 2022 states are approximate and flagged for verification in the code comments.

---

## Paper

The full paper is available in `writing/article.md` and as a formatted document at [[(https://github.com/JoelNithishKumar/snap-takeup-revisit/blob/b730cb376f58a4800e064b47517b93b76ad0aff1/writing/Administrative%20Burden%20and%20SNAP%20Participation%20-%20A%20State-Panel%20Analysis%20with%20Evidence%20from%20the%20Emergency%20Allotment%20Rollback.docx)]. It is intended as a pre-doctoral research writing sample demonstrating familiarity with applied microeconomics methods, reproducible empirical workflows, and honest communication of identification assumptions and data limitations.

---

## License

Data from USDA and Census Bureau is in the public domain. Code in this repository is released under the MIT License.
