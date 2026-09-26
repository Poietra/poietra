///|
/// Scene-wide structure is independent of Composition poses and track timing.
/// A preparation pass shares one ordered list and lazily resolved parent graph.
pub struct ObjectLayout {
  priv ordered : Array[SceneObject]
  priv has_parents : Bool
  priv mut cached_hierarchy : Hierarchy?
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
    cached_hierarchy: None,
    cached_indices: None,
  }
}

///|
fn ObjectLayout::hierarchy(self : ObjectLayout) -> Hierarchy {
  match self.cached_hierarchy {
    Some(hierarchy) => hierarchy
    None => {
      let hierarchy = prepare_hierarchy(self.ordered)
      self.cached_hierarchy = Some(hierarchy)
      hierarchy
    }
  }
}

///|
priv struct IndexedHierarchy {
  parents : Array[Int]
  indices : Map[String, Int]
}

///|
/// Parent slots are topological, while item slots preserve authored paint order.
/// Some objects have no pose at either endpoint; their slot still inherits its
/// parent's matrix so descendants see exactly the same effective hierarchy.
priv struct TransitionHierarchy {
  parents : Array[Int]
  slots : Array[Int]
}

///|
fn ObjectLayout::transition_hierarchy(
  self : ObjectLayout,
  items : Array[AnimatedObject],
) -> TransitionHierarchy {
  let graph = match self.cached_indices {
    Some(graph) => graph
    None => {
      let hierarchy = self.hierarchy()
      let indices : Map[String, Int] = Map([])
      for index, id in hierarchy.order {
        indices[id] = index
      }
      let graph : IndexedHierarchy = {
        indices,
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
  {
    parents: graph.parents,
    slots: items.map(fn(item) { graph.indices[item.object.id] }),
  }
}

///|
fn TransitionHierarchy::matrices(
  self : TransitionHierarchy,
  states : Array[ObjectState?],
) -> Array[Affine] {
  let matrices : Array[Affine] = []
  for index, parent in self.parents {
    let parent = if parent < 0 { Affine::identity() } else { matrices[parent] }
    matrices.push(
      match states[index] {
        Some(state) => parent.compose(state.local_matrix())
        None => parent
      },
    )
  }
  matrices
}
