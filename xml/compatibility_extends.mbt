// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend XmlError with Debug::{to_repr}

///|
pub extend XmlError with Eq::{not_equal, equal}

///|
pub extend Attribute with Debug::{to_repr}

///|
pub extend Attribute with Eq::{not_equal, equal}

///|
pub extend Node with Debug::{to_repr}

///|
pub extend Node with Eq::{not_equal, equal}

///|
pub extend Element with Debug::{to_repr}

///|
pub extend Element with Eq::{not_equal, equal}

///|
pub extend ParseOptions with Debug::{to_repr}

///|
pub extend ParseOptions with Eq::{not_equal, equal}
