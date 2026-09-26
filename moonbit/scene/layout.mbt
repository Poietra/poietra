///|
/// Scene-wide structure is independent of Composition poses and track timing.
/// A preparation pass shares one ordered list and lazily resolved parent graph.
priv struct ObjectLayout {
  ordered : Array[SceneObject]
  has_parents : Bool
  mut cached_hierarchy : Hierarchy?
}

///|
fn object_layout(ordered : Array[SceneObject]) -> ObjectLayout {
  {
    ordered,
    has_parents: ordered.any(fn(object) { object.parentId is Some(_) }),
    cached_hierarchy: None,
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
