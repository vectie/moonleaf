// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend ArchivePolicy with Debug::{to_repr}

///|
pub extend ArchivePolicy with Eq::{not_equal, equal}

///|
pub extend PackageError with Debug::{to_repr}

///|
pub extend PackageError with Eq::{not_equal, equal}

///|
pub extend Part with Debug::{to_repr}

///|
pub extend Part with Eq::{not_equal, equal}

///|
pub extend Relationship with Debug::{to_repr}

///|
pub extend Relationship with Eq::{not_equal, equal}

///|
pub extend Package with Debug::{to_repr}

///|
pub extend Package with Eq::{not_equal, equal}
