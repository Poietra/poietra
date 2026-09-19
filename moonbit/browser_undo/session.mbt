///|
pub struct Session {
  manager : @core.Any
  yjs : @core.Any
  root : @core.Any
  peer_audio : @weak.WeakSet[@core.Any]
  peer_tracks : @weak.WeakSet[@core.Any]
  peer_timings : @weak.WeakSet[@core.Any]
  peer_activations : @weak.WeakMap[@core.Any, @weak.WeakSet[@core.Any]]
  peer_objects : @weak.WeakSet[@core.Any]
  peer_compositions : @weak.WeakSet[@core.Any]
  peer_transitions : @weak.WeakSet[@core.Any]
  retained_tracks : @weak.WeakSet[@core.Any]
  mut observer : @core.Any
  mut destroyed : Bool
  mut counts : Preserved
}

///|
struct Preserved {
  audio : Int
  objects : Int
  durations : Int
  compositions : Int
}

///|
fn empty_counts() -> Preserved {
  { audio: 0, objects: 0, durations: 0, compositions: 0, }
}

///|
pub fn create_session(manager : @core.Any, yjs : @core.Any) -> Session {
  let root = manager._get("doc")._call("getMap", [@core.any("project")])
  let session : Session = {
    manager,
    yjs,
    root,
    peer_audio: @weak.WeakSet::new(),
    peer_tracks: @weak.WeakSet::new(),
    peer_timings: @weak.WeakSet::new(),
    peer_activations: @weak.WeakMap::new(),
    peer_objects: @weak.WeakSet::new(),
    peer_compositions: @weak.WeakSet::new(),
    peer_transitions: @weak.WeakSet::new(),
    retained_tracks: @weak.WeakSet::new(),
    observer: @core.undefined(),
    destroyed: false,
    counts: empty_counts(),
  }
  session.observer = @core.any(fn(
    events : FixedArray[@core.Any],
    transaction : @core.Any,
  ) {
    if !session.destroyed && !truthy(transaction._get("local")) {
      session.remember_peer_edits(events)
    }
  })
  root._call("observeDeep", [session.observer]) |> ignore
  session
}

///|
pub fn destroy_session(session : Session) -> Unit {
  if session.destroyed {
    return
  }
  session.destroyed = true
  session.root._call("unobserveDeep", [session.observer]) |> ignore
  session.observer = @core.undefined()
}

///|
pub fn session_counts(session : Session) -> @core.Any {
  @core.from_entries([
    ("audioTracks", @core.any(session.counts.audio)),
    ("objects", @core.any(session.counts.objects)),
    ("durations", @core.any(session.counts.durations)),
    ("compositions", @core.any(session.counts.compositions)),
  ])
}

///|
fn Session::remember_object(
  self : Session,
  scene : String,
  id : String,
) -> Unit {
  let object = self.shared(["scenes", scene, "objects", id])
  if self.is_map(object) {
    self.peer_objects.add(object) |> ignore
  }
}

///|
fn Session::remember_peer_edits(
  self : Session,
  events : FixedArray[@core.Any],
) -> Unit {
  for event in events {
    let path = event_path(event)
    if path.length() < 3 || path[0] != "scenes" {
      continue
    }
    let changed = if instance_of(event, self.yjs._get("YMapEvent")) {
      keys(event._get("keysChanged"))
    } else {
      []
    }
    let parents : FixedArray[String] = if path.length() == 3 {
      changed
    } else {
      [path[3]]
    }
    if path[2] == "audioTracks" {
      for id in parents {
        let track = self.shared(["scenes", path[1], "audioTracks", id])
        if self.is_map(track) {
          self.peer_audio.add(track) |> ignore
        }
      }
      continue
    }
    let remembered = match path[2] {
      "compositions" => Some(self.peer_compositions)
      "transitions" => Some(self.peer_transitions)
      _ => None
    }
    if remembered is Some(remembered) {
      for id in parents {
        let parent = self.shared(["scenes", path[1], path[2], id])
        if self.is_map(parent) {
          remembered.add(parent) |> ignore
        }
      }
    }
    if path[2] == "objects" {
      for id in parents {
        self.remember_object(path[1], id)
      }
      continue
    }
    let collection = match path[2] {
      "compositions" => "states"
      "transitions" => "tracks"
      _ => continue
    }
    if (path.length() == 4 && !changed.contains(collection)) ||
      (path.length() >= 5 && path[4] != collection) {
      continue
    }
    for parent in parents {
      let entries = self.shared(["scenes", path[1], path[2], parent, collection])
      if !self.is_map(entries) {
        continue
      }
      let ids : FixedArray[String] = if path.length() < 5 {
        keys(entries)
      } else if path.length() == 5 {
        changed
      } else {
        [path[5]]
      }
      for id in ids {
        self.remember_object(path[1], id)
        let track = get(entries, id)
        if collection != "tracks" || !self.is_map(track) {
          continue
        }
        self.peer_tracks.add(track) |> ignore
        let changed_timings = if path.length() > 6 {
          [path[6]]
        } else if path.length() == 6 {
          changed.iter().to_array()
        } else {
          timing_keys()
        }
        for key in timing_keys() {
          let timing = get(track, key)
          if changed_timings.contains(key) && self.is_map(timing) {
            self.peer_timings.add(timing) |> ignore
          }
        }
        // Retain an activation identity, not an automatic parent's lifetime.
        // A peer's independent timing does not depend on a promoted base track.
        let base = [
          "type", "start", "duration", "easing", "order", "path", "implicit",
        ]
        let edits_base = path.length() < 6 ||
          (if path.length() == 6 {
            changed.iter().any(fn(key) { base.contains(key) })
          } else {
            base.contains(path[6])
          })
        let activation = get(track._get("_map"), "implicit")
        if edits_base &&
          @core.equal(get(track, "implicit"), @core.any(false)) &&
          !@core.is_nullish(activation) {
          let edits = match self.peer_activations.get(track) {
            Some(edits) => edits
            None => {
              let edits = @weak.WeakSet::new()
              self.peer_activations.set(track, edits) |> ignore
              edits
            }
          }
          edits.add(activation) |> ignore
        }
      }
    }
  }
}
