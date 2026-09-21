///|
// JS inheritance only; the decision to publish a clock is MoonBit-owned.
extern "js" fn extend_awareness(
  base : @core.Any,
  select : (String, FixedArray[@core.Any], Double) -> FixedArray[@core.Any]?,
) -> @core.Any =
  #|(Base, select) => class extends Base { emit(name, args) { const selected = select(name, args, this.clientID); if (selected !== undefined) super.emit(name, selected); } }

///|
/// This server-authoritative transport never relays other clients' presence.
/// Remote `change` events still update UI, and local clock renewals/removal still
/// emit `update`. Use only with disableBc=true and the room's fanout server.
pub fn owned_awareness_class(base : @core.Any) -> @core.Any {
  extend_awareness(base, fn(event, args, client_id) {
    if event != "update" {
      return Some(args)
    }
    let changed = args[0]
    let owned = @core.new_object()
    let mut any = false
    for key in ["added", "updated", "removed"] {
      let ids : FixedArray[Double] = changed._get(key).cast()
      let own = ids.iter().any(fn(id) { id == client_id })
      any = any || own
      owned._set(
        key,
        @core.any(if own { FixedArray::make(1, client_id) } else { [] }),
      )
    }
    if any {
      Some([owned, args[1]])
    } else {
      None
    }
  })
}
