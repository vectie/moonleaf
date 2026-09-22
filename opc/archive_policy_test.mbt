///|
fn policy_fixture(
  extra_entries : Array[(String, FixedArray[Byte])],
) -> FixedArray[Byte] {
  let entries = [
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<Types xmlns=\"urn:content-types\"/>"),
    ),
  ]
  entries.append(extra_entries)
  @fzip.zip_sync(entries)
}

///|
fn exact_boundary_policy(
  content : FixedArray[Byte],
) -> @opc.ArchivePolicy raise {
  let infos = @fzip.unzip_list(content)
  let mut max_compressed = 1
  let mut max_uncompressed = 1
  let mut total_uncompressed = 0
  let mut max_ratio = 1
  let mut max_depth = 1
  let mut max_path_length = 1
  for info in infos {
    if info.size > max_compressed {
      max_compressed = info.size
    }
    if info.original_size > max_uncompressed {
      max_uncompressed = info.original_size
    }
    total_uncompressed += info.original_size
    let ratio = if info.original_size == 0 {
      1
    } else if info.size == 0 {
      200
    } else {
      (info.original_size + info.size - 1) / info.size
    }
    if ratio > max_ratio {
      max_ratio = ratio
    }
    let mut depth = 0
    for component in info.name.split("/") {
      if !component.is_empty() {
        depth += 1
      }
    }
    if depth > max_depth {
      max_depth = depth
    }
    if info.name.length() > max_path_length {
      max_path_length = info.name.length()
    }
  }
  {
    max_compressed_input_bytes: content.length(),
    max_entries: infos.length(),
    max_entry_compressed_bytes: max_compressed,
    max_entry_uncompressed_bytes: max_uncompressed,
    max_total_uncompressed_bytes: total_uncompressed,
    max_compression_ratio: max_ratio,
    max_path_depth: max_depth,
    max_path_length,
  }
}

///|
fn expect_archive_rejection(
  content : FixedArray[Byte],
  policy : @opc.ArchivePolicy,
  message_part : String,
) -> Unit raise {
  try @opc.open_with_policy(content, policy) catch {
    @opc.PackageError::InvalidPackage(message) =>
      if !message.contains(message_part) {
        fail("expected '\{message}' to contain '\{message_part}'")
      }
    _ => fail("expected InvalidPackage")
  } noraise {
    _ => fail("expected archive policy rejection")
  }
}

///|
fn corrupt_first_central_crc(
  content : FixedArray[Byte],
) -> FixedArray[Byte] raise {
  let corrupted = content.copy()
  for index in 0..<(corrupted.length() - 20) {
    if corrupted[index] == b'\x50' &&
      corrupted[index + 1] == b'\x4b' &&
      corrupted[index + 2] == b'\x01' &&
      corrupted[index + 3] == b'\x02' {
      corrupted[index + 16] = corrupted[index + 16].lxor(b'\x01')
      return corrupted
    }
  }
  fail("fixture has no central-directory entry")
}

///|
test "archive policy exact boundaries pass and preserve unknown parts" {
  let content = policy_fixture([
    ("custom/data.bin", [b'\x00', b'\xff', b'\x80']),
    ("word/document.xml", @fzip.str_to_u8("<document>before</document>")),
  ])
  let policy = exact_boundary_policy(content)
  let archive = @opc.open_with_policy(content, policy)
  assert_eq(archive.text("word/document.xml"), "<document>before</document>")
  assert_true(
    archive.part("custom/data.bin").unwrap().content == [0x00, 0xff, 0x80],
  )
  let edited = archive.replace_text(
    "word/document.xml", "<document>after</document>",
  )
  let saved = @opc.save(edited)
  let reopened = @opc.open(saved)
  assert_eq(reopened.text("word/document.xml"), "<document>after</document>")
  assert_true(
    reopened.part("custom/data.bin").unwrap().content == [0x00, 0xff, 0x80],
  )
}

///|
test "archive policy validates input entry and total size ceilings" {
  let content = policy_fixture([
    ("a.bin", [b'a', b'a', b'a', b'a', b'a', b'a']),
    ("b.bin", [b'b', b'b', b'b', b'b', b'b', b'b']),
  ])
  let defaults = @opc.ArchivePolicy::default()
  expect_archive_rejection(
    content,
    {
      ..defaults,
      max_compressed_input_bytes: 1,
      max_entry_compressed_bytes: 1,
    },
    "max_compressed_input_bytes",
  )
  expect_archive_rejection(
    content,
    { ..defaults, max_entry_compressed_bytes: 1, },
    "max_entry_compressed_bytes",
  )
  expect_archive_rejection(
    content,
    {
      ..defaults,
      max_entry_uncompressed_bytes: 5,
      max_total_uncompressed_bytes: 1024,
    },
    "max_entry_uncompressed_bytes",
  )
  expect_archive_rejection(
    content,
    {
      ..defaults,
      max_entry_uncompressed_bytes: 40,
      max_total_uncompressed_bytes: 40,
    },
    "max_total_uncompressed_bytes",
  )
}

///|
test "archive policy rejects too many entries and excessive compression ratio" {
  let many = policy_fixture([("one.bin", [b'1']), ("two.bin", [b'2'])])
  expect_archive_rejection(
    many,
    { ..@opc.ArchivePolicy::default(), max_entries: 2, },
    "max_entries",
  )
  let repeated = FixedArray::make(4096, b'A')
  let compressed = policy_fixture([("word/repeated.bin", repeated)])
  expect_archive_rejection(
    compressed,
    { ..@opc.ArchivePolicy::default(), max_compression_ratio: 1, },
    "max_compression_ratio",
  )
}

///|
test "archive policy rejects depth and path-length violations" {
  let deep = policy_fixture([("a/b/c/file.xml", @fzip.str_to_u8("<x/>"))])
  expect_archive_rejection(
    deep,
    { ..@opc.ArchivePolicy::default(), max_path_depth: 3, },
    "max_path_depth",
  )
  let long = policy_fixture([
    ("word/a-very-long-part-name.xml", @fzip.str_to_u8("<x/>")),
  ])
  expect_archive_rejection(
    long,
    { ..@opc.ArchivePolicy::default(), max_path_length: 19, },
    "max_path_length",
  )
}

///|
test "archive policy rejects traversal aliases and duplicates" {
  let defaults = @opc.ArchivePolicy::default()
  let traversal = policy_fixture([("../evil.xml", @fzip.str_to_u8("<x/>"))])
  expect_archive_rejection(traversal, defaults, "parent component")
  let slash_alias = policy_fixture([
    ("word//document.xml", @fzip.str_to_u8("<x/>")),
  ])
  expect_archive_rejection(slash_alias, defaults, "empty, dot, or parent")
  let duplicate = @fzip.zip_sync([
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<Types xmlns=\"urn:content-types\"/>"),
    ),
    ("word/document.xml", @fzip.str_to_u8("<one/>")),
    ("word/document.xml", @fzip.str_to_u8("<two/>")),
  ])
  expect_archive_rejection(duplicate, defaults, "duplicate or aliased")
  let case_alias = @fzip.zip_sync([
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<Types xmlns=\"urn:content-types\"/>"),
    ),
    ("word/item.xml", @fzip.str_to_u8("<one/>")),
    ("WORD/ITEM.XML", @fzip.str_to_u8("<two/>")),
  ])
  expect_archive_rejection(case_alias, defaults, "duplicate or aliased")
}

///|
test "archive open requires CRC integrity" {
  let content = policy_fixture([
    ("word/document.xml", @fzip.str_to_u8("<document>ok</document>")),
  ])
  let corrupted = corrupt_first_central_crc(content)
  expect_archive_rejection(
    corrupted,
    @opc.ArchivePolicy::default(),
    "CRC integrity verification failed",
  )
}
