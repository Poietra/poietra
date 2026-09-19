///|
extern "js" fn new_shared_map(host : @core.Any) -> @core.Any =
  #|host => new host.Map()

///|
extern "js" fn new_shared_array(host : @core.Any) -> @core.Any =
  #|host => new host.Array()

///|
extern "js" fn insert_shared(
  array : @core.Any,
  values : FixedArray[@core.Any],
) -> Unit =
  #|(array, values) => { array.insert(0, values); }

///|
extern "js" fn is_array(value : @core.Any) -> Bool = "Array.isArray"

///|
extern "js" fn map_has(value : @core.Any, key : String) -> Bool =
  #|(map, key) => map.has(key)

///|
extern "js" fn map_get(value : @core.Any, key : String) -> @core.Any =
  #|(map, key) => map.get(key)

///|
extern "js" fn map_set(
  value : @core.Any,
  key : String,
  item : @core.Any,
) -> Unit =
  #|(map, key, item) => { map.set(key, item); }

///|
extern "js" fn map_delete(value : @core.Any, key : String) -> Unit =
  #|(map, key) => { map.delete(key); }

///|
extern "js" fn map_values(value : @core.Any) -> FixedArray[@core.Any] =
  #|map => Array.from(map.values())

///|
extern "js" fn map_keys(value : @core.Any) -> FixedArray[String] =
  #|map => Array.from(map.keys())

///|
extern "js" fn same_value(a : @core.Any, b : @core.Any) -> Bool = "Object.is"

///|
extern "js" fn transact(
  doc : @core.Any,
  f : () -> Unit,
  origin : @core.Any,
) -> Unit =
  #|(doc, f, origin) => { doc.transact(f, origin); }

///|
pub fn to_shared(value : @core.Any, host : @core.Any) -> @core.Any {
  if is_array(value) {
    let values : FixedArray[@core.Any] = value.cast()
    let result = new_shared_array(host)
    insert_shared(
      result,
      FixedArray::makei(values.length(), fn(i) { to_shared(values[i], host) }),
    )
    result
  } else if !@core.is_null(value) && @core.typeof_(value) == "object" {
    let result = new_shared_map(host)
    for key in @core.object_keys(value) {
      map_set(result, key, to_shared(value._get(key), host))
    }
    result
  } else {
    value
  }
}

///|
pub fn initialize_document(
  doc : @core.Any,
  project : @core.Any,
  host : @core.Any,
) -> Unit {
  let root = shared_map(doc)
  if has_version(root) {
    return
  }
  transact(
    doc,
    fn() {
      for key in @core.object_keys(project) {
        map_set(root, key, to_shared(project._get(key), host))
      }
    },
    @core.any("initialize"),
  )
}

///|
pub fn get_shared(
  doc : @core.Any,
  path : FixedArray[String],
  host : @core.Any,
) -> @core.Any {
  let mut node = shared_map(doc)
  for key in path {
    if !is_instance(node, host._get("Map")) {
      return @core.undefined()
    }
    node = map_get(node, key)
  }
  node
}

///|
pub fn get_value(
  doc : @core.Any,
  path : FixedArray[String],
  host : @core.Any,
) -> @core.Any {
  let value = get_shared(doc, path, host)
  if is_instance(value, host._get("AbstractType")) {
    shared_json(value)
  } else {
    value
  }
}

///|
pub fn apply_changes(
  doc : @core.Any,
  input : FixedArray[@core.Any],
  origin : @core.Any,
  host : @core.Any,
) -> Unit {
  let changes = Array::makei(input.length(), fn(i) {
    let change = input[i]
    let value = change._get("value")
    let mutation = if @core.is_undefined(value) {
      @collaboration.Remove
    } else {
      @collaboration.Put(value)
    }
    @collaboration.Change::{
      path: decode_array(change._get("path"), fn(v) { v.cast() }),
      mutation,
    }
  })
  let resolved = @collaboration.resolve_changes(changes, fn(path) {
    let parent = get_shared(
      doc,
      FixedArray::makei(path.length(), fn(i) { path[i] }),
      host,
    )
    if is_instance(parent, host._get("Map")) {
      Some(parent)
    } else {
      None
    }
  })
  match resolved {
    Err(error) => {
      let message = match error {
        InvalidPath => "Invalid edit path"
        MissingParent(path) =>
          "The edit target no longer exists: " + path.join(".")
      }
      @core.throw_error(message)
    }
    Ok(changes) =>
      transact(
        doc,
        fn() {
          for change in changes {
            match change.mutation {
              Remove => map_delete(change.parent, change.key)
              Put(value) =>
                if !same_value(map_get(change.parent, change.key), value) {
                  map_set(change.parent, change.key, to_shared(value, host))
                }
            }
          }
        },
        origin,
      )
  }
}

///|
extern "js" fn make_change(
  path : FixedArray[String],
  value : @core.Any,
) -> @core.Any =
  #|(path, value) => ({path, value})

///|
pub fn changes_for(
  base : FixedArray[String],
  value : @core.Any,
) -> FixedArray[@core.Any] {
  let keys = @core.object_keys(value)
  FixedArray::makei(keys.length(), fn(i) {
    let path = FixedArray::makei(base.length() + 1, fn(j) {
      if j < base.length() {
        base[j]
      } else {
        keys[i]
      }
    })
    make_change(path, value._get(keys[i]))
  })
}

///|
pub fn ensure_scene_audio_tracks(doc : @core.Any, host : @core.Any) -> Bool {
  let scenes = map_get(shared_map(doc), "scenes")
  if !is_instance(scenes, host._get("Map")) {
    return false
  }
  let mut changed = false
  transact(
    doc,
    fn() {
      for scene in map_values(scenes) {
        if is_instance(scene, host._get("Map")) &&
          !map_has(scene, "audioTracks") {
          map_set(scene, "audioTracks", new_shared_map(host))
          changed = true
        }
      }
    },
    @core.any("initialize-media"),
  )
  changed
}

///|
priv struct AnimationMigration {
  mut dirty : Bool
}

///|
let migrations : WeakCache[AnimationMigration] = WeakCache::new()

///|
extern "js" fn observe_deep(
  root : @core.Any,
  observer : (FixedArray[@core.Any]) -> Unit,
) -> Unit =
  #|(root, observer) => { root.observeDeep(observer); }

///|
extern "js" fn unobserve_deep(
  root : @core.Any,
  observer : (FixedArray[@core.Any]) -> Unit,
) -> Unit =
  #|(root, observer) => { root.unobserveDeep(observer); }

///|
extern "js" fn event_keys(event : @core.Any) -> FixedArray[String] =
  #|event => Array.from(event.keysChanged)

///|
extern "js" fn string_value(value : @core.Any) -> String = "String"

///|
fn animation_migration(doc : @core.Any, host : @core.Any) -> AnimationMigration {
  if migrations.has(doc) {
    return migrations.get(doc)
  }
  let state = { dirty: true, }
  migrations.set(doc, state)
  let root = shared_map(doc)
  let observer = fn(events : FixedArray[@core.Any]) {
    for event in events {
      if !is_instance(event, host._get("YMapEvent")) {
        continue
      }
      let keys = event_keys(event)
      if @collaboration.invalidates_automatic_tracks(
          decode_array(event._get("path"), string_value),
          Array::makei(keys.length(), fn(i) { keys[i] }),
        ) {
        state.dirty = true
        break
      }
    }
  }
  observe_deep(root, observer)
  doc_on(doc, "destroy", fn(_) {
    unobserve_deep(root, observer)
    migrations.remove(doc)
  })
  state
}

///|
pub fn ensure_scene_animation_tracks(doc : @core.Any, host : @core.Any) -> Bool {
  let state = animation_migration(doc, host)
  if !state.dirty {
    return false
  }
  let scenes = map_get(shared_map(doc), "scenes")
  if !is_instance(scenes, host._get("Map")) {
    state.dirty = false
    return false
  }
  let mut changed = false
  transact(
    doc,
    fn() {
      for scene in map_values(scenes) {
        if !is_instance(scene, host._get("Map")) {
          continue
        }
        let objects = map_get(scene, "objects")
        let transitions = map_get(scene, "transitions")
        if !is_instance(objects, host._get("Map")) ||
          !is_instance(transitions, host._get("Map")) {
          continue
        }
        for transition in map_values(transitions) {
          if !is_instance(transition, host._get("Map")) {
            continue
          }
          let tracks = map_get(transition, "tracks")
          let duration = map_get(transition, "duration")
          if !is_instance(tracks, host._get("Map")) ||
            @core.typeof_(duration) != "number" {
            continue
          }
          for id in map_keys(objects) {
            if !map_has(tracks, id) {
              let track = @scene.default_track(id, duration.cast())
              let value = encode({ ..track, implicit: Some(true), })
              put_own(value, "path", @core.null())
              map_set(tracks, id, to_shared(value, host))
              changed = true
            }
          }
        }
      }
    },
    @core.any("initialize-animation-tracks"),
  )
  state.dirty = false
  changed
}
