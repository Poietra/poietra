///|
test "late feedback expiration cannot remove a newer gesture or another scope" {
  let empty : FeedbackState = { revision: 0, entry: None, }
  let first = reduce_feedback(
    empty,
    Report("scene-a", Some({ label: "Moved", detail: None, kind: Complete, })),
  )
  let next = reduce_feedback(
    first,
    Report(
      "scene-b",
      Some({ label: "Dragging", detail: Some("12 px"), kind: Active, }),
    ),
  )
  let after_old_timer = reduce_feedback(next, Expire(first.revision))
  assert_eq(after_old_timer.entry.unwrap().scope, "scene-b")
  assert_eq(after_old_timer.entry.unwrap().status.label, "Dragging")
  assert_eq(
    announcement(after_old_timer.entry.map(fn(entry) { entry.status })),
    "",
  )
  let done = reduce_feedback(
    next,
    Report(
      "scene-b",
      Some({ label: "Moved", detail: Some("12 px"), kind: Complete, }),
    ),
  )
  assert_eq(
    announcement(done.entry.map(fn(entry) { entry.status })),
    "Moved · 12 px",
  )
  assert_true(reduce_feedback(done, Expire(done.revision)).entry is None)
}
