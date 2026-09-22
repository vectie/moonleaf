// Explicitly preserve the derived public methods on MoonBit 20260920+.

///|
pub extend MoonLeafError with Debug::{to_repr}

///|
pub extend MoonLeafError with Eq::{not_equal, equal}

///|
pub extend DocumentFormat with Debug::{to_repr}

///|
pub extend DocumentFormat with Eq::{not_equal, equal}

///|
pub extend DocumentCapabilities with Debug::{to_repr}

///|
pub extend DocumentCapabilities with Eq::{not_equal, equal}

///|
pub extend DocumentDiagnostic with Debug::{to_repr}

///|
pub extend DocumentDiagnostic with Eq::{not_equal, equal}

///|
pub extend DocumentSessionError with Debug::{to_repr}

///|
pub extend DocumentSessionError with Eq::{not_equal, equal}
