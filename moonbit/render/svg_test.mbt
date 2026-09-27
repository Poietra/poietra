///|
test "XML escaping preserves spans, pairs and whitespace around replacements" {
  assert_eq(escape_xml(""), "")
  assert_eq(escape_xml("日本語😀\t\r\n"), "日本語😀\t\r\n")
  assert_eq(escape_xml("<&\"'>"), "&lt;&amp;&quot;&apos;&gt;")
  let broken = String::from_array([
    'A',
    (0xd800).unsafe_to_char(),
    'B',
    (0xdc00).unsafe_to_char(),
    'C',
  ])
  assert_eq(escape_xml(broken), "A�B�C")
  let removed = String::from_array([
    'A',
    (0).unsafe_to_char(),
    (0xb).unsafe_to_char(),
    (0xffff).unsafe_to_char(),
    'B',
  ])
  assert_eq(escape_xml(removed), "AB")
  assert_eq(
    escape_xml("😀<&日本語>😀"),
    "😀&lt;&amp;日本語&gt;😀",
  )
  let span = String::from_array(Array::make(10000, 'a')[:])
  assert_eq(escape_xml(span), span)
  assert_eq(escape_xml(span + "&" + span), span + "&amp;" + span)
}
