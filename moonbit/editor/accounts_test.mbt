///|
test "private project search and order do not change the source list" {
  let projects : Array[AccountProject] = [
    { room_id: "z", name: "Zebra", updated_at: 1.0, },
    { room_id: "b", name: "alpha", updated_at: 3.0, },
    { room_id: "a", name: "ALPHA", updated_at: 3.0, },
    { room_id: "j", name: "春の動画", updated_at: 2.0, },
  ]
  let ids = fn(rows : Array[AccountProject]) {
    rows.map(fn(row) { row.room_id })
  }
  assert_eq(ids(account_project_view(projects, "", RecentlyUpdated)), [
    "a", "b", "j", "z",
  ])
  assert_eq(ids(account_project_view(projects, "", ProjectName)), [
    "a", "b", "z", "j",
  ])
  assert_eq(ids(account_project_view(projects, "  aLpHa  ", ProjectName)), [
    "a", "b",
  ])
  assert_eq(ids(account_project_view(projects, "動画", RecentlyUpdated)), [
    "j",
  ])
  assert_true(
    account_project_view(projects, "missing", RecentlyUpdated).is_empty(),
  )
  assert_eq(ids(projects), ["z", "b", "a", "j"])
}
