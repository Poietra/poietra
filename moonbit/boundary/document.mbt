///|
/// Host cache keys are Yjs shared types; cached values are immutable JS snapshots.
/// Weak keys release replaced/deleted branches when Yjs and Undo release them.
#external
priv type WeakCache[V]

///|
extern "js" fn weak_new() -> @core.Any =
  #|() => new WeakMap()

///|
extern "js" fn weak_has(cache : @core.Any, key : @core.Any) -> Bool =
  #|(cache, key) => cache.has(key)

///|
extern "js" fn weak_get(cache : @core.Any, key : @core.Any) -> @core.Any =
  #|(cache, key) => cache.get(key)

///|
extern "js" fn weak_set(
  cache : @core.Any,
  key : @core.Any,
  value : @core.Any,
) -> Unit =
  #|(cache, key, value) => { cache.set(key, value); }

///|
extern "js" fn weak_remove(cache : @core.Any, key : @core.Any) -> Unit =
  #|(cache, key) => { cache.delete(key); }

///|
fn[V] WeakCache::new() -> WeakCache[V] {
  weak_new().cast()
}

///|
fn[V] WeakCache::has(self : WeakCache[V], key : @core.Any) -> Bool {
  weak_has(@core.any(self), key)
}

///|
fn[V] WeakCache::get(self : WeakCache[V], key : @core.Any) -> V {
  weak_get(@core.any(self), key).cast()
}

///|
fn[V] WeakCache::set(self : WeakCache[V], key : @core.Any, value : V) -> Unit {
  weak_set(@core.any(self), key, @core.any(value))
}

///|
fn[V] WeakCache::remove(self : WeakCache[V], key : @core.Any) -> Unit {
  weak_remove(@core.any(self), key)
}

///|
enum TransactionPhase {
  Mutating
  Observing
  Idle
} derive(Eq)

///|
priv struct DocumentSnapshots {
  mut pending : Int
  mut phase : TransactionPhase
  mut raw : WeakCache[@core.Any]
  scenes : WeakCache[@core.Any]
  projects : WeakCache[@core.Any]
}

///|
let documents : WeakCache[DocumentSnapshots] = WeakCache::new()

///|
extern "js" fn shared_map(doc : @core.Any) -> @core.Any =
  #|doc => doc.getMap('project')

///|
extern "js" fn has_version(root : @core.Any) -> Bool =
  #|root => root.has('version')

///|
extern "js" fn shared_json(value : @core.Any) -> @core.Any =
  #|value => value.toJSON()

///|
extern "js" fn shared_entries(
  value : @core.Any,
) -> FixedArray[FixedArray[@core.Any]] =
  #|value => Array.from(value.entries())

///|
extern "js" fn shared_array(value : @core.Any) -> FixedArray[@core.Any] =
  #|value => value.toArray()

///|
extern "js" fn shared_parent(value : @core.Any) -> @core.Any =
  #|value => value.parent

///|
extern "js" fn changed_types(transaction : @core.Any) -> FixedArray[@core.Any] =
  #|transaction => Array.from(transaction.changed.keys())

///|
extern "js" fn is_instance(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
extern "js" fn freeze(value : @core.Any) -> @core.Any =
  #|value => Object.freeze(value)

///|
extern "js" fn put_own(
  value : @core.Any,
  key : String,
  item : @core.Any,
) -> Unit =
  #|(value, key, item) => { Object.defineProperty(value, key, {value: item, writable: true, enumerable: true, configurable: true}); }

///|
extern "js" fn doc_on(
  doc : @core.Any,
  event : String,
  listener : (@core.Any) -> Unit,
) -> Unit =
  #|(doc, event, listener) => { doc.on(event, listener); }

///|
extern "js" fn doc_off(
  doc : @core.Any,
  event : String,
  listener : (@core.Any) -> Unit,
) -> Unit =
  #|(doc, event, listener) => { doc.off(event, listener); }

///|
/// Yjs exposes no public 'currently mutating' query. This single guarded bridge
/// covers first reads inside an already-open transaction; lifecycle events cover
/// all subsequent reads, including transactions queued by observers.
extern "js" fn has_active_transaction(doc : @core.Any) -> Bool =
  #|doc => doc._transaction != null

///|
fn invalidate(state : DocumentSnapshots, transaction : @core.Any) -> Unit {
  for changed in changed_types(transaction) {
    let mut node = changed
    while !@core.is_nullish(node) {
      state.raw.remove(node)
      node = shared_parent(node)
    }
  }
}

///|
fn document_snapshots(doc : @core.Any) -> DocumentSnapshots {
  if documents.has(doc) {
    return documents.get(doc)
  }
  let state = {
    phase: Idle,
    pending: if has_active_transaction(doc) {
      1
    } else {
      0
    },
    raw: WeakCache::new(),
    scenes: WeakCache::new(),
    projects: WeakCache::new(),
  }
  let before : (@core.Any) -> Unit = fn(_) {
    state.pending += 1
    state.phase = Mutating
  }
  let observing : (@core.Any) -> Unit = fn(transaction) {
    invalidate(state, transaction)
    state.pending = (state.pending - 1).max(0)
    state.phase = if state.pending == 0 { Observing } else { Mutating }
  }
  let after : (@core.Any) -> Unit = fn(_) {
    if state.pending > 0 {
      state.raw = WeakCache::new()
    }
    state.pending = 0
    state.phase = Idle
  }
  doc_on(doc, "beforeTransaction", before)
  doc_on(doc, "beforeObserverCalls", observing)
  doc_on(doc, "afterAllTransactions", after)
  doc_on(doc, "destroy", fn(_) {
    doc_off(doc, "beforeTransaction", before)
    doc_off(doc, "beforeObserverCalls", observing)
    doc_off(doc, "afterAllTransactions", after)
    documents.remove(doc)
  })
  documents.set(doc, state)
  state
}

///|
fn freeze_tree(value : @core.Any) -> @core.Any {
  if !@core.is_nullish(value) && @core.typeof_(value) == "object" {
    for key in @core.object_keys(value) {
      freeze_tree(value._get(key)) |> ignore
    }
    freeze(value)
  } else {
    value
  }
}

///|
fn shared_snapshot(
  value : @core.Any,
  host : @core.Any,
  cache : WeakCache[@core.Any],
) -> @core.Any {
  if !is_instance(value, host._get("AbstractType")) {
    return if !@core.is_nullish(value) && @core.typeof_(value) == "object" {
      freeze_tree(snapshot(value))
    } else {
      value
    }
  }
  if cache.has(value) {
    return cache.get(value)
  }
  let result = if is_instance(value, host._get("Map")) {
    let result = @core.new_object()
    for entry in shared_entries(value) {
      put_own(result, entry[0].cast(), shared_snapshot(entry[1], host, cache))
    }
    freeze(result)
  } else if is_instance(value, host._get("Array")) {
    let items = shared_array(value)
    let result = FixedArray::makei(items.length(), fn(i) {
      shared_snapshot(items[i], host, cache)
    })
    freeze(@core.any(result))
  } else {
    freeze_tree(shared_json(value))
  }
  cache.set(value, result)
  result
}

///|
pub fn read_project(doc : @core.Any, host : @core.Any) -> @core.Any {
  let root = shared_map(doc)
  let state = document_snapshots(doc)
  if !has_version(root) {
    return @core.null()
  }
  // Reads within a mutation must see all preceding writes, even when no observer
  // has run. Never put such transient values into the persistent cache.
  if state.phase == Mutating || has_active_transaction(doc) {
    return project_structure_view(shared_json(root))
  }
  let raw = shared_snapshot(root, host, state.raw)
  if state.projects.has(raw) {
    return state.projects.get(raw)
  }
  let projected = project_view(raw, fn(scene) {
    if state.scenes.has(scene) {
      return state.scenes.get(scene)
    }
    let result = scene_view(scene, true)
    // Only projection-owned containers need freezing; retained subtrees already
    // belong to immutable cached snapshots.
    for id in @core.object_keys(result._get("compositions")) {
      freeze(result._get("compositions")._get(id)) |> ignore
    }
    for id in @core.object_keys(result._get("transitions")) {
      freeze(result._get("transitions")._get(id)) |> ignore
    }
    freeze(result._get("compositions")) |> ignore
    freeze(result._get("transitions")) |> ignore
    freeze(result._get("compositionOrder")) |> ignore
    freeze(result) |> ignore
    state.scenes.set(scene, result)
    result
  })
  freeze(projected._get("scenes")) |> ignore
  freeze(projected._get("sceneOrder")) |> ignore
  freeze(projected) |> ignore
  state.projects.set(raw, projected)
  projected
}
