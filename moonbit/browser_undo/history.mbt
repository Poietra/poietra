///|
fn field_history(map : @core.Any, key : String) -> Array[@core.Any] {
  let history = []
  let mut item = get(map._get("_map"), key)
  while !@core.is_nullish(item) {
    history.push(item)
    item = item._get("left")
  }
  history
}

///|
fn item_value(item : @core.Any) -> @core.Any {
  let content : FixedArray[@core.Any] = item
    ._get("content")
    ._call("getContent", [])
    .cast()
  if content.is_empty() {
    @core.undefined()
  } else {
    content[0]
  }
}

///|
fn Session::field_after_undo(
  self : Session,
  action : @core.Any,
  map : @core.Any,
  key : String,
) -> @core.Any {
  let history = field_history(map, key)
  let current = if history.is_empty() { @core.undefined() } else { history[0] }
  let mut changes_current = false
  for historical in history {
    if !self.deleted(action._get("insertions"), historical) {
      continue
    }
    let mut item = historical
    while !@core.is_nullish(item._get("redone")) {
      item = self.yjs._call("getItem", [
        self.manager._get("doc")._get("store"),
        item._get("redone"),
      ])
    }
    if @core.equal(item, current) {
      changes_current = true
      break
    }
  }
  if !changes_current {
    return get(map, key)
  }
  for item in history {
    if self.deleted(action._get("deletions"), item) &&
      !self.deleted(action._get("insertions"), item) {
      return item_value(item)
    }
  }
  @core.undefined()
}

///|
// A restored child may still be tombstoned until the actual Yjs transaction.
fn Session::field_after_step(
  self : Session,
  action : @core.Any,
  map : @core.Any,
  key : String,
) -> @core.Any {
  let item = get(map._get("_map"), key)
  if !@core.is_nullish(item) &&
    truthy(item._get("deleted")) &&
    self.deleted(action._get("deletions"), item) &&
    !self.deleted(action._get("insertions"), item) {
    return item_value(item)
  }
  self.field_after_undo(action, map, key)
}

///|
fn Session::without_items(
  self : Session,
  source : @core.Any,
  omitted : Array[@core.Any],
) -> @core.Any {
  // Group once by the full JS client number. Each client's interval difference
  // sorts once and walks linearly instead of copying all ranges per omitted Item.
  let cuts : @collection.JsMap[Double, Array[@collaboration.ClockSpan]] = @collection.JsMap::new()
  for item in omitted {
    let id = item._get("id")
    let client : Double = id._get("client").cast()
    let spans = match cuts.get(client) {
      Some(spans) => spans
      None => {
        let spans = []
        cuts.set(client, spans) |> ignore
        spans
      }
    }
    spans.push({
      clock: id._get("clock").cast(),
      length: item._get("length").cast(),
    })
  }
  let result = self.yjs._call("createDeleteSet", [])
  let clients : @collection.JsMap[Double, FixedArray[@core.Any]] = source
    ._get("clients")
    .cast()
  let output : @collection.JsMap[Double, FixedArray[@core.Any]] = result
    ._get("clients")
    .cast()
  clients.forEach(fn(ranges, client) {
    let source = ranges
      .iter()
      .map(fn(range) {
        @collaboration.ClockSpan::{
          clock: range._get("clock").cast(),
          length: range._get("len").cast(),
        }
      })
      .to_array()
    let remaining = @collaboration.omit_clock_spans(
      source,
      match cuts.get(client) {
        Some(spans) => spans
        None => []
      },
    )
    if !remaining.is_empty() {
      output.set(
        client,
        FixedArray::makei(remaining.length(), fn(i) {
          @core.from_entries([
            ("clock", @core.any(remaining[i].clock)),
            ("len", @core.any(remaining[i].length)),
          ])
        }),
      )
      |> ignore
    }
  })
  result
}
