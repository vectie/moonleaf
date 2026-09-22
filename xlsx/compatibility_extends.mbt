// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend XlsxError with Debug::{to_repr}

///|
pub extend XlsxError with Eq::{not_equal, equal}

///|
pub extend InspectWarning with Debug::{to_repr}

///|
pub extend InspectWarning with Eq::{not_equal, equal}

///|
pub extend DisplayKind with Debug::{to_repr}

///|
pub extend DisplayKind with Eq::{not_equal, equal}

///|
pub extend DateTimeMetadata with Debug::{to_repr}

///|
pub extend DateTimeMetadata with Eq::{not_equal, equal}

///|
pub extend InspectedCell with Debug::{to_repr}

///|
pub extend InspectedCell with Eq::{not_equal, equal}
