// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend PptxError with Debug::{to_repr}

///|
pub extend PptxError with Eq::{not_equal, equal}
