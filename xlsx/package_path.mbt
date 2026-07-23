///|
fn normalize_package_path(path : String) -> String {
  let components : Array[String] = []
  for component in path.split("/") {
    let component = "\{component}"
    match component {
      "" | "." => ()
      ".." => ignore(components.pop())
      component => components.push(component)
    }
  }
  components.join("/")
}

///|
fn resolve_relationship_target(source_part : String, target : String) -> String {
  if target.has_prefix("/") {
    return normalize_package_path("\{target[1:]}")
  }
  match source_part.rev_find("/") {
    Some(index) => normalize_package_path("\{source_part[:index + 1]}\{target}")
    None => normalize_package_path(target)
  }
}
