///|
/// Scene-wide structure is independent of Composition poses and track timing.
/// A preparation pass shares one ordered list and lazily resolved parent graph.
pub struct ObjectLayout {
  priv ordered : Array[SceneObject]
  priv has_parents : Bool
  priv mut cached_indices : IndexedHierarchy?
}

///|
/// Own the ordered metadata list; each evaluation reads the current poses.
pub fn ObjectLayout::new(ordered : Array[SceneObject]) -> ObjectLayout {
  object_layout(ordered.copy())
}

///|
fn object_layout(ordered : Array[SceneObject]) -> ObjectLayout {
  {
    ordered,
    has_parents: ordered.any(fn(object) { object.parentId is Some(_) }),
    cached_indices: None,
  }
}

///|
priv struct IndexedHierarchy {
  order : Array[String]
  parents : Array[Int]
  indices : Map[String, Int]
  paint_slots : Array[Int]
  clippers : Array[Bool]?
}

///|
/// Parent slots are topological, while item slots preserve authored paint order.
/// Some objects have no pose at either endpoint; their slot still inherits its
/// parent's matrix so descendants see exactly the same effective hierarchy.
priv struct TransitionHierarchy {
  parents : Array[Int]
  slots : Array[Int]
  clippers : Array[Bool]?
}

///|
fn ObjectLayout::indexed_hierarchy(self : ObjectLayout) -> IndexedHierarchy {
  match self.cached_indices {
    Some(graph) => graph
    None => {
      let hierarchy = prepare_hierarchy(self.ordered)
      let indices : Map[String, Int] = Map([])
      for index, id in hierarchy.order {
        indices[id] = index
      }
      let graph : IndexedHierarchy = {
        order: hierarchy.order,
        indices,
        clippers: if self.ordered.any(fn(o) {
            o.kind == Rectangle && o.clipChildren == Some(true)
          }) {
          let ids = Set::from_array(
            self.ordered
            .filter(fn(o) {
              o.kind == Rectangle && o.clipChildren == Some(true)
            })
            .map(fn(o) { o.id }),
          )
          Some(hierarchy.order.map(fn(id) { ids.contains(id) }))
        } else {
          None
        },
        paint_slots: self.ordered.map(fn(object) { indices[object.id] }),
        parents: hierarchy.order.map(fn(id) {
          match hierarchy.parents.get(id) {
            Some(parent) => indices[parent]
            None => -1
          }
        }),
      }
      self.cached_indices = Some(graph)
      graph
    }
  }
}

///|
fn ObjectLayout::transition_hierarchy(
  self : ObjectLayout,
  items : Array[AnimatedObject],
) -> TransitionHierarchy {
  let graph = self.indexed_hierarchy()
  {
    parents: graph.parents,
    clippers: graph.clippers,
    slots: items.map(fn(item) { graph.indices[item.object.id] }),
  }
}

///|
fn TransitionHierarchy::matrices(
  self : TransitionHierarchy,
  states : Array[ObjectState?],
) -> Array[Affine] {
  indexed_matrices(self.parents, states)
}

///|
priv struct CompositionPoses {
  slots : Array[Int]
  states : Array[ObjectState?]
  matrices : Array[Affine]
  clips : Array[Array[Clip]?]?
}

///|
fn ObjectLayout::composition_poses(
  self : ObjectLayout,
  states : Map[String, ObjectState],
) -> CompositionPoses {
  let graph = self.indexed_hierarchy()
  let states = graph.order.map(fn(id) { states.get(id) })
  let matrices = indexed_matrices(graph.parents, states)
  {
    slots: graph.paint_slots,
    states,
    matrices,
    clips: graph.clippers.map(fn(clippers) {
      indexed_clips(graph.parents, clippers, states, matrices)
    }),
  }
}

///|
/// Share inherited clip arrays between siblings. Hidden parents still define
/// transforms and clipping; each drawable keeps its independent visibility.
fn indexed_clips(
  parents : Array[Int],
  clippers : Array[Bool],
  states : Array[ObjectState?],
  matrices : Array[Affine],
) -> Array[Array[Clip]?] {
  let inherited : Array[Array[Clip]?] = []
  let descendants : Array[Array[Clip]?] = []
  for index, parent in parents {
    let clips = if parent < 0 { None } else { descendants[parent] }
    inherited.push(clips)
    descendants.push(
      if clippers[index] {
        let next = clips.map(fn(items) { items.copy() }).unwrap_or([])
        next.push({
          world: matrices[index],
          width: states[index].map(fn(s) { s.width.abs() }).unwrap_or(0.0),
          height: states[index].map(fn(s) { s.height.abs() }).unwrap_or(0.0),
        })
        Some(next)
      } else {
        clips
      },
    )
  }
  inherited
}

///|
// Both still and animated frames use the same topological traversal. Only its
// inputs differ; world matrices belong to this evaluation and are never cached.
fn indexed_matrices(
  parents : Array[Int],
  states : Array[ObjectState?],
) -> Array[Affine] {
  let matrices : Array[Affine] = Array(capacity=parents.length())
  let identity = Affine::identity()
  for index, parent in parents {
    let parent = if parent < 0 { identity } else { matrices[parent] }
    matrices.push(
      match states[index] {
        Some(state) => parent.compose(state.local_matrix())
        None => parent
      },
    )
  }
  matrices
}
