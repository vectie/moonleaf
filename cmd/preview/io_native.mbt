///|
/// POSIX file and stream adapter. The document work stays in MoonBit; these
/// calls only cross the operating-system boundary.
#borrow(path)
extern "c" fn posix_open(path : Bytes, flags : Int, mode : Int) -> Int = "open"

///|
#borrow(path, mode)
extern "c" fn exclusive_fopen(path : Bytes, mode : Bytes) -> Int64 = "fopen"

///|
extern "c" fn file_descriptor(file : Int64) -> Int = "fileno"

///|
extern "c" fn set_file_mode(fd : Int, mode : Int) -> Int = "fchmod"

///|
extern "c" fn set_umask(mask : Int) -> Int = "umask"

///|
extern "c" fn close_file(file : Int64) -> Int = "fclose"

///|
#borrow(buffer)
extern "c" fn posix_read(fd : Int, buffer : Bytes, count : UInt64) -> Int64 = "read"

///|
#borrow(buffer)
extern "c" fn posix_write(fd : Int, buffer : Bytes, count : UInt64) -> Int64 = "write"

///|
extern "c" fn posix_close(fd : Int) -> Int = "close"

///|
fn c_path(path : String) -> Bytes {
  for char in path.iter() {
    if char == '\u{0000}' {
      abort("MoonLeaf path contains a NUL byte")
    }
  }
  @utf8.encode(path + "\u{0000}")
}

///|
fn read_fd(fd : Int) -> FixedArray[Byte] {
  let output : Array[Byte] = []
  let buffer = Bytes::make(8192, 0)
  for ;; {
    let count = posix_read(fd, buffer, buffer.length().to_uint64())
    if count < 0 {
      abort("MoonLeaf file read failed")
    }
    if count == 0 {
      break
    }
    for i in 0..<count.to_int() {
      output.push(buffer[i])
    }
  }
  FixedArray::from_array(output)
}

///|
fn read_file(path : String) -> FixedArray[Byte] {
  let fd = posix_open(c_path(path), 0, 0)
  if fd < 0 {
    abort("MoonLeaf cannot open source file")
  }
  let bytes = read_fd(fd)
  if posix_close(fd) != 0 {
    abort("MoonLeaf cannot close source file")
  }
  bytes
}

///|
fn write_fd(fd : Int, bytes : Bytes) -> Unit {
  let mut offset = 0
  while offset < bytes.length() {
    let end = (offset + 8192).min(bytes.length())
    let chunk = bytes[offset:end].to_owned()
    let count = posix_write(fd, chunk, chunk.length().to_uint64())
    if count <= 0 {
      abort("MoonLeaf file write failed")
    }
    offset += count.to_int()
  }
}

///|
fn write_file(path : String, bytes : FixedArray[Byte]) -> Unit {
  // fopen's x mode creates exclusively without a variadic open(2) call.
  // MoonBit's native FFI does not pass C varargs on the macOS arm64 ABI.
  let previous_umask = set_umask(0o077)
  let file = exclusive_fopen(c_path(path), c_path("wbx"))
  ignore(set_umask(previous_umask))
  if file == 0 {
    abort("MoonLeaf cannot create output file")
  }
  let fd = file_descriptor(file)
  if fd < 0 || set_file_mode(fd, 0o600) != 0 {
    ignore(close_file(file))
    abort("MoonLeaf cannot secure output file")
  }
  write_fd(fd, Bytes::from_array(bytes))
  if close_file(file) != 0 {
    abort("MoonLeaf cannot close output file")
  }
}

///|
fn read_stdin() -> String {
  @utf8.decode(Bytes::from_array(read_fd(0))) catch {
    _ => abort("MoonLeaf stdin is not UTF-8")
  }
}

///|
fn report_error(message : String) -> Unit {
  write_fd(2, @utf8.encode(message + "\n"))
}

///|
/// Keep the established Node argv shape for the shared command dispatcher.
fn cli_args() -> Array[String] {
  let raw = @env.args()
  let args : Array[String] = [raw[0]]
  for arg in raw {
    args.push(arg)
  }
  args
}
