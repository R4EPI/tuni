#' Produces counts with respective proportions from specified variables in a dataframe.
#'
#' This function has been superseeded by [tab_linelist()]. Please use that
#' function instead.
#'
#' @param df A dataframe (e.g. your linelist)
#'
#' @param counter A name of the variable (in quotation marks) that you would
#'   like to have as rows.
#'
#' @param grouper A name of the variable (in quotation marks) that you would
#'   like to have as columns.
#'
#' @param multiplier What you would like to have your proportions as (default
#'   is per 100).
#'
#' @param digits The number of decimal places you would like in your
#'   proportions (default is 1).
#'
#' @param proptotal A TRUE/FALSE variable specifying whether you would
#'   proportions to be of total cases.The default is FALSE and returns
#'   proportions for each column.
#'
#' @param coltotals Add column totals on the end
#'
#' @param rowtotals Add row totals (only sums counts)
#'
#' @param explicit_missing if `TRUE`, missing values will be marked as
#' `Missing` and tabulated. Defaults to `FALSE`, where missing values are
#' excluded from the computation
#'
#' @details The `descriptive()` function returns a single table with counts and
#'   proportions of a categorical variable (`counter`). Adding a grouper adds
#'   more columns, stratifying "n" and "prop", the option `coltotals = TRUE`
#'   adds one row and `rowtotals = TRUE` (useful if a grouper is present) adds
#'   one column.
#'
#'   The `multi_descriptive()` function allows you to combine several counter
#'   variables into a single table where each row represents a variable and the
#'   columns represent counts and proportions of the values within those
#'   variables. This function assumes that all of the variables have the same
#'   values (e.g. Yes/No values) and atttempts no correction.
#'
#' @importFrom dplyr group_by ungroup bind_rows summarise_all funs count mutate mutate_at
#' @importFrom tidyr complete gather unite spread
#' @importFrom rlang sym "!!" ".data" ":="
#' @importFrom stats setNames
#' @keywords internal
descriptive <- function(df, counter, grouper = NULL, multiplier = 100, digits = 1,
                        proptotal = FALSE, coltotals = FALSE, rowtotals = FALSE,
                        explicit_missing = TRUE) {


  # translate the variable names to character
  counter <- tidyselect::vars_select(colnames(df), !!rlang::enquo(counter))
  grouper <- tidyselect::vars_select(colnames(df), !!rlang::enquo(grouper))

  has_grouper <- length(grouper) == 1
  sym_count <- rlang::sym(counter)

  # Check if counter is an integer and force factor ----------------------------

  if (is.numeric(df[[counter]])) {
    warning(glue::glue("converting `{counter}` to a factor"), call. = FALSE)
    df[[counter]] <- epikit::fac_from_num(df[[counter]])
  }

  if (is.logical(df[[counter]])) {
    df[[counter]] <- factor(df[[counter]], levels = c("TRUE", "FALSE"))
  }

  df[[counter]] <- factor(df[[counter]])
  if (has_grouper) df[[grouper]] <- factor(df[[grouper]])

  # Filter missing data --------------------------------------------------------

  if (explicit_missing) {
    df[[counter]] <- forcats::fct_explicit_na(df[[counter]], "Missing")
  } else {
    nas <- is.na(df[[counter]])
    if (sum(nas) > 0) warning(glue::glue("Removing {sum(nas)} missing values"), call. = FALSE)
    df <- df[!nas, , drop = FALSE]
  }

  # Apply grouping -------------------------------------------------------------

  if (has_grouper) {
    # This grouper var will always have explicit missing.
    sym_group <- rlang::sym(grouper)
    df[[grouper]] <- forcats::fct_explicit_na(df[[grouper]], "Missing")
    count_data <- dplyr::group_by(df, !!sym_group, .drop = FALSE)
  } else {
    count_data <- df
  }

  # Get counts and proportions -------------------------------------------------

  count_data <- dplyr::count(count_data, !!sym_count, .drop = FALSE)

  if (proptotal) {
    count_data <- dplyr::mutate(count_data,
      proportion = .data$n / nrow(df) * multiplier,
    )
  } else {
    count_data <- dplyr::mutate(count_data,
      proportion = .data$n / sum(.data$n) * multiplier,
    )
  }

  # Widen grouping data --------------------------------------------------------

  if (has_grouper) {
    count_data <- widen_tabulation(count_data,
      cod = !!sym_count,
      st = !!sym_group,
      pretty = FALSE
    )
  }

  # fill in the counting data that didn't make it
  count_data <- dplyr::mutate_if(count_data, is.numeric, tidyr::replace_na, 0)

  # Calculate totals for each column -------------------------------------------

  if (coltotals == TRUE) {
    count_data <- dplyr::ungroup(count_data)
    # change first column (with var levels) in to a character (for rbinding)
    count_data <- dplyr::mutate(count_data, !!sym_count := as.character(!!sym_count))
    # summarise all columns that are numeric, make first col "Total", bind as a row
    csummaries <- dplyr::summarise_if(count_data, is.numeric, sum, na.rm = TRUE)
    count_data <- dplyr::bind_rows(count_data, csummaries)
    count_data[nrow(count_data), 1] <- "Total"
  }

  # Calculate totals for all rows ----------------------------------------------

  if (rowtotals == TRUE) {
    # add columns which have "_n" in the name
    count_data <- mutate(count_data,
      Total = rowSums(count_data[, grep("( n$|^n$)", colnames(count_data))], na.rm = TRUE)
    )
  }

  count_data
}

