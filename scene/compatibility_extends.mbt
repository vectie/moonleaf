// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend DocumentKind with Debug::{to_repr}

///|
pub extend DocumentKind with Eq::{not_equal, equal}

///|
pub extend Warning with Debug::{to_repr}

///|
pub extend Warning with Eq::{not_equal, equal}

///|
pub extend TextStyle with Debug::{to_repr}

///|
pub extend TextStyle with Eq::{not_equal, equal}

///|
pub extend TextRun with Debug::{to_repr}

///|
pub extend TextRun with Eq::{not_equal, equal}

///|
pub extend TextBlock with Debug::{to_repr}

///|
pub extend TextBlock with Eq::{not_equal, equal}

///|
pub extend TextDocument with Debug::{to_repr}

///|
pub extend TextDocument with Eq::{not_equal, equal}

///|
pub extend CellValue with Debug::{to_repr}

///|
pub extend CellValue with Eq::{not_equal, equal}

///|
pub extend Cell with Debug::{to_repr}

///|
pub extend Cell with Eq::{not_equal, equal}

///|
pub extend CellRange with Debug::{to_repr}

///|
pub extend CellRange with Eq::{not_equal, equal}

///|
pub extend Sheet with Debug::{to_repr}

///|
pub extend Sheet with Eq::{not_equal, equal}

///|
pub extend Workbook with Debug::{to_repr}

///|
pub extend Workbook with Eq::{not_equal, equal}

///|
pub extend Rect with Debug::{to_repr}

///|
pub extend Rect with Eq::{not_equal, equal}

///|
pub extend SlideElement with Debug::{to_repr}

///|
pub extend SlideElement with Eq::{not_equal, equal}

///|
pub extend Slide with Debug::{to_repr}

///|
pub extend Slide with Eq::{not_equal, equal}

///|
pub extend Presentation with Debug::{to_repr}

///|
pub extend Presentation with Eq::{not_equal, equal}

///|
pub extend Document with Debug::{to_repr}

///|
pub extend Document with Eq::{not_equal, equal}
