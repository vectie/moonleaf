///|
extern "c" fn test_getpid() -> Int = "getpid"

///|
#borrow(path)
extern "c" fn test_unlink(path : Bytes) -> Int = "unlink"

///|
test "native adapter reads binary files and reserves outputs exclusively" {
  let path = "/tmp/moonleaf-preview-io-\{test_getpid()}.bin"
  ignore(test_unlink(c_path(path)))
  let bytes : FixedArray[Byte] = [0, 1, 255, 10, 0]
  write_file(path, bytes)
  assert_eq(read_file(path), bytes)
  let second = exclusive_fopen(c_path(path), c_path("wbx"))
  assert_true(file_is_null(second))
  assert_eq(test_unlink(c_path(path)), 0)
}
