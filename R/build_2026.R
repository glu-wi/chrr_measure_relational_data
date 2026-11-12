# Build the provisional 2026 relational tables from the CHR&R
# March 25, 2026 Supplemental Data Release (analytic CSV).
#
# CHR&R has not published a 2026 relational release. This script reshapes the
# wide analytic supplement into the relational layout used for 2010-2025 so the
# rows can be stacked with earlier years. Fields that the supplement does not
# provide (z-scores, ranks, map groups, ...) are NA. If CHR&R publishes an
# official 2026 relational release, it should replace everything this script
# writes.
#
# Outputs (run from the repo root):
#   2026/t_measure_data_2026.parquet        county rows
#   2026/t_measure_data_years_2026.parquet  county rows + years_used
#   2026/t_state_data_2026.parquet          national + state rows
#   2026/t_state_data_years_2026.parquet    national + state rows + years_used
#   2026/t_race_data_2026.parquet           race/ethnicity values, all geographies
#   t_measure.parquet, t_measure_years.parquet  2026 rows appended (replaced on re-run)

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

source_url <- paste0(
  "https://www.countyhealthrankings.org/sites/default/files/media/document/",
  "analytic_supplement_20260325%5B1%5D.csv"
)
source_tag <- "analytic_supplement_20260325"
data_year  <- 2026L
tz         <- "America/Chicago"
release_ts <- as.POSIXct("2026-03-25 00:00:00", tz = tz)
build_ts   <- as.POSIXct(format(Sys.time(), tz = tz, usetz = FALSE), tz = tz)
ref_year   <- 2025L # template year for schemas and measure metadata

# Years of data, from the supplement codebook
# (Analytic_Dataset_Codebook_Supplemental_Release_20260325.pdf).
years_used <- tribble(
  ~measure_id, ~years_used,
    1L, "2021-2023",   147L, "2021-2023",   127L, "2021-2023",   128L, "2020-2023",
  129L, "2017-2023",    36L, "2023",         37L, "2018-2024",   144L, "2023",
   60L, "2023",         61L, "2023",         11L, "2023",         42L, "2023",
  145L, "2023",        161L, "2019-2023",     2L, "2023",        183L, "2023",
  155L, "2023",        133L, "2019 & 2023", 139L, "2023",         14L, "2018-2024",
   45L, "2023",         49L, "2023",        134L, "2019-2023",   138L, "2021-2023",
    9L, "2023",         70L, "2023",          4L, "2022",         62L, "2025",
   88L, "2023",          5L, "2023",         50L, "2023",         85L, "2023",
    3L, "2023",        122L, "2023",        131L, "2025",        154L, "2020-2024",
  124L, "2024",        166L, "2020-2024",   181L, "2023",         23L, "2024",
   44L, "2020-2024",    65L, "2023-2024",   151L, "2020-2024",   170L, "2025",
  135L, "2019-2023",   140L, "2023",         15L, "2017-2023",    39L, "2017-2023",
  148L, "2019-2023",   184L, "2023"
)

# ---- download -------------------------------------------------------------
csv_path <- file.path(tempdir(), "analytic_supplement_20260325.csv")
download.file(source_url, csv_path, mode = "wb", quiet = TRUE)
message("Downloaded ", source_url, " on ", format(Sys.Date()))

# "." is the SAS missing-value marker that appears in a few columns (e.g. v183 CIs).
raw <- read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE,
                na.strings = c("", "NA", "."), strip.white = TRUE)
names(raw) <- tolower(names(raw)) # v005_race_AIAN -> v005_race_aian
stopifnot(!anyDuplicated(names(raw)))

id_cols <- c("statecode", "countycode")
v_cols  <- grep("^v\\d{3}_", names(raw), value = TRUE)

# ---- long form: one row per geography x measure x field -------------------
long <- raw |>
  select(all_of(c(id_cols, v_cols))) |>
  mutate(across(all_of(v_cols), as.numeric)) |>
  pivot_longer(all_of(v_cols), names_to = "col", values_to = "value") |>
  mutate(
    measure_id = as.integer(sub("^v(\\d{3})_.*$", "\\1", col)),
    field      = sub("^v\\d{3}_", "", col)
  ) |>
  transmute(
    state_fips  = as.integer(statecode),
    county_fips = as.integer(countycode),
    measure_id, field, value
  )

stopifnot(setequal(unique(long$measure_id), years_used$measure_id))

is_race <- grepl("^race_", long$field)

# ---- measure / state values -----------------------------------------------
value_map <- c(
  rawvalue          = "raw_value",
  numerator         = "numerator",
  denominator       = "denominator",
  cilow             = "ci_low",
  cihigh            = "ci_high",
  rawalternatevalue = "other_data_1", # population-to-provider ratio
  other_data_1      = "other_data_1",
  flag              = "flag"          # 1 = unreliable (RSE > 20%), 2 = suppressed
)
unknown <- setdiff(unique(long$field[!is_race]), names(value_map))
if (length(unknown)) stop("Unmapped supplement fields: ", paste(unknown, collapse = ", "))

values <- long[!is_race, ] |>
  mutate(field = value_map[field]) |>
  pivot_wider(names_from = field, values_from = value) |>
  mutate(
    year        = data_year,
    correction  = 0L,
    # Same coding as the relational `reliability` column:
    # 0 = reliable, 1 = unreliable, 2 = suppressed / no value.
    reliability = case_when(
      !is.na(flag)       ~ as.integer(flag),
      is.na(raw_value)   ~ 2L,
      TRUE               ~ 0L
    ),
    last_updated = release_ts,
    source       = source_tag
  ) |>
  select(-flag)

# ---- race values ----------------------------------------------------------
race <- long[is_race, ] |>
  mutate(
    field = sub("_cilow$", "_ci_low", field),
    field = sub("_cihigh$", "_ci_high", field),
    field = sub("_flag2$", "_flag", field)
  ) |>
  group_by(state_fips, county_fips, measure_id) |>
  filter(any(!is.na(value))) |> # drop geography x measure rows with no race data at all
  ungroup() |>
  pivot_wider(names_from = field, values_from = value) |>
  mutate(
    year         = data_year,
    correction   = 0L,
    last_updated = release_ts,
    source       = source_tag
  )

# ---- shape to the reference-year schema ------------------------------------
# Every column of the reference table, in its order and type, NA-filled where
# the supplement has nothing, plus `source` as the final column. Columns that
# are all-null in the reference year get a concrete type if 2026 has values.
to_ref_schema <- function(df, ref_path, extra = character()) {
  ref <- open_dataset(ref_path)$schema
  out <- list()
  for (f in ref$fields) {
    v <- if (f$name %in% names(df)) df[[f$name]] else rep(NA, nrow(df))
    type <- f$type
    if (type$ToString() == "null" && any(!is.na(v))) {
      type <- if (all(v == round(v), na.rm = TRUE)) int32() else float64()
    }
    out[[f$name]] <- if (type$ToString() == "null") {
      Array$create(v, type = null())
    } else {
      Array$create(v)$cast(type) # all-NA logical vectors cast cleanly to any type
    }
  }
  for (x in extra) out[[x]] <- Array$create(df[[x]], type = utf8())
  dropped <- setdiff(names(df), c(ref$names, extra))
  if (length(dropped)) stop("Columns not in reference schema: ", paste(dropped, collapse = ", "))
  do.call(arrow_table, out)
}

ref <- function(name) sprintf("%d/%s_%d.parquet", ref_year, name, ref_year)
out <- function(name) sprintf("%d/%s_%d.parquet", data_year, name, data_year)
dir.create(as.character(data_year), showWarnings = FALSE)

arrange_geo <- function(df) arrange(df, measure_id, state_fips, county_fips)

county <- values |> filter(county_fips != 0) |> arrange_geo()
state  <- values |> filter(county_fips == 0) |> arrange_geo()
race   <- race |> arrange_geo()

with_years <- function(df) {
  df |>
    select(-source) |>
    left_join(years_used, by = "measure_id") |>
    mutate(source = source_tag)
}

write_parquet(to_ref_schema(county, ref("t_measure_data"), "source"), out("t_measure_data"))
write_parquet(to_ref_schema(with_years(county), ref("t_measure_data_years"), "source"),
              out("t_measure_data_years"))
write_parquet(to_ref_schema(state, ref("t_state_data"), "source"), out("t_state_data"))
write_parquet(to_ref_schema(with_years(state), ref("t_state_data_years"), "source"),
              out("t_state_data_years"))
write_parquet(to_ref_schema(race, ref("t_race_data"), "source"), out("t_race_data"))

# ---- lookup tables: append 2026 measure metadata ---------------------------
# 2026 rows copy the 2025 metadata for the measures in the supplement; the
# years_used come from the codebook. Re-running replaces earlier 2026 rows.
append_measures <- function(path, add_years) {
  # mmap = FALSE: on Windows a memory-mapped file cannot be overwritten.
  tbl  <- read_parquet(path, as_data_frame = FALSE, mmap = FALSE)
  sch  <- tbl$schema
  df   <- as.data.frame(tbl)
  rm(tbl); invisible(gc())
  new  <- df |>
    filter(year == ref_year, measure_id %in% .env$years_used$measure_id) |>
    mutate(year = data_year, last_updated = build_ts)
  stopifnot(nrow(new) == nrow(years_used))
  if (add_years) {
    new <- new |> select(-years_used) |> left_join(years_used, by = "measure_id")
  }
  combined <- bind_rows(filter(df, year != data_year), new[names(df)]) |>
    arrange(year, measure_id)
  write_parquet(arrow_table(combined, schema = sch), path)
}

append_measures("t_measure.parquet", add_years = FALSE)
append_measures("t_measure_years.parquet", add_years = TRUE)

message(
  "Wrote ", data_year, " tables: ",
  nrow(county), " county rows, ", nrow(state), " state rows, ",
  nrow(race), " race rows across ", n_distinct(values$measure_id), " measures."
)
