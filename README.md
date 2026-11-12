The parquet files in this repo were created from the csv files from County Health Rankings & Roadmaps, which are available at [https://zenodo.org/records/18332002](https://zenodo.org/records/18332002).

## 2026 (provisional)

CHR&R has not published a 2026 relational release. The `2026/` folder is a **provisional** build from the CHR&R
[Supplemental Data Release (March 25, 2026)](https://www.countyhealthrankings.org/health-data/methodology-and-sources/data-documentation)
analytic CSV, reshaped into the same layout as 2010–2025 by [`R/build_2026.R`](R/build_2026.R).

- Source file: `analytic_supplement_20260325[1].csv`, downloaded 2026-11-11. Codebook: `Analytic_Dataset_Codebook_Supplemental_Release_20260325[1].pdf`. CHR&R lists both under its 2025 Annual Data Release.
- Rows are labeled `year = 2026`, and every 2026 data table has an extra last column, `source = "analytic_supplement_20260325"`. Apart from that column, the 2026 tables have the same columns and types as the 2025 tables, so they can be stacked.
- It covers **50 measures**, not the 95 in 2025: 1, 2, 3, 4, 5, 9, 11, 14, 15, 23, 36, 37, 39, 42, 44, 45, 49, 50, 60, 61, 62, 65, 70, 85, 88, 122, 124, 127, 128, 129, 131, 133, 134, 135, 138, 139, 140, 144, 145, 147, 148, 151, 154, 155, 161, 166, 170, 181, 183, 184.
- These files are included: `t_measure_data_2026`, `t_measure_data_years_2026`, `t_state_data_2026`, `t_state_data_years_2026` and `t_race_data_2026`. There are no `t_category_data`, `t_factor_data` or `t_focus_area_data` files for 2026, because the supplement has no z-scores, ranks or health groups.
- These fields are always NA in 2026: `z_score*`, `rank_value`, `rank_ready`, `display`, `county_ranked`, `map_group`, `area_to_highlight`, `trend_graph`, `show_details`, `state_min`, `state_max`, and `other_data_*` except `other_data_1`.
- `other_data_1` holds the population-to-provider ratio for measures 4, 62, 88 and 131, and the supplement's `v161_other_data_1` value for measure 161.
- `reliability` uses the 2025 coding: 0 = reliable, 1 = unreliable (relative standard error over 20%, flagged only for measures 1 and 37), 2 = suppressed or no value. The race `*_flag` columns come from the supplement's `_flag2` columns and use the same codes.
- `years_used` in the `_years` tables, and in `t_measure_years`, comes from the supplement codebook.
- `t_measure.parquet` and `t_measure_years.parquet` have 2026 rows for the 50 measures. Their metadata is copied from 2025. `t_benchmark`, `t_category`, `t_factor`, `t_focus_area` and `t_map_legend` have no 2026 rows.
- Connecticut: the supplement mixes counties and planning regions depending on the measure, as 2025 does.
- Living Wage (170): the codebook says these values are left out of the downloadable files, but the CSV contains them, so they are included here as published.

If CHR&R publishes an official 2026 relational release, it should fully replace the `2026/` folder and the 2026 rows in the lookup tables.

To rebuild from the repo root, run `Rscript R/build_2026.R`. It needs the arrow, dplyr and tidyr packages. Re-running replaces the 2026 outputs.
