// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend LayoutAudit with Eq::{not_equal, equal}

///|
pub extend ParagraphMetadata with Eq::{not_equal, equal}

///|
pub extend ParagraphMetadata with Debug::{to_repr}

///|
pub extend RunMetadata with Eq::{not_equal, equal}

///|
pub extend RunMetadata with Debug::{to_repr}

///|
pub extend ParagraphInfo with Eq::{not_equal, equal}

///|
pub extend ParagraphInfo with Debug::{to_repr}

///|
pub extend TableCellInfo with Eq::{not_equal, equal}

///|
pub extend TableCellInfo with Debug::{to_repr}

///|
pub extend TableRowInfo with Eq::{not_equal, equal}

///|
pub extend TableRowInfo with Debug::{to_repr}

///|
pub extend TableInfo with Eq::{not_equal, equal}

///|
pub extend TableInfo with Debug::{to_repr}

///|
pub extend DocxFlowBlock with Eq::{not_equal, equal}

///|
pub extend DocxFlowBlock with Debug::{to_repr}

///|
pub extend SectionInfo with Eq::{not_equal, equal}

///|
pub extend SectionInfo with Debug::{to_repr}

///|
pub extend ResourceInfo with Eq::{not_equal, equal}

///|
pub extend ResourceInfo with Debug::{to_repr}

///|
pub extend DocxDocument with Eq::{not_equal, equal}

///|
pub extend DocxDocument with Debug::{to_repr}

///|
pub extend DocxPreviewDocument with Eq::{not_equal, equal}

///|
pub extend DocxPreviewDocument with Debug::{to_repr}

///|
pub extend PaginationProfile with Eq::{not_equal, equal}

///|
pub extend PaginationProfile with Debug::{to_repr}

///|
pub extend DocxPage with Eq::{not_equal, equal}

///|
pub extend DocxPage with Debug::{to_repr}

///|
pub extend PagedDocxDocument with Eq::{not_equal, equal}

///|
pub extend PagedDocxDocument with Debug::{to_repr}

///|
pub extend DocxError with Debug::{to_repr}

///|
pub extend DocxError with Eq::{not_equal, equal}
