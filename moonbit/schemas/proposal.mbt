///|
fn operation(
  action : String,
  fields : Map[String, @zod.ZodSchema],
) -> @zod.ZodSchema {
  fields["action"] = @zod.literal(@core.any(action))
  @zod.object(fields)
}

///|
fn object_fields() -> Map[String, @zod.ZodSchema] {
  {
    "compositionId": @zod.string(),
    "name": @zod.string(),
    "x": @zod.number(),
    "y": @zod.number(),
    "width": @zod.number(),
    "height": @zod.number(),
    "fill": @zod.string(),
    "text": @zod.string(),
    "fontSize": @zod.number(),
  }
}

///|
fn proposal_schema(resolved : Bool) -> @zod.ZodSchema {
  let coordinate = @zod.number().finite().min(-10000).max(10000)
  let point = @zod.object({ "x": coordinate, "y": coordinate })
  let bezier = @zod.object({ "c1": point, "c2": point })
  let reference = @zod.string().regex("^@[a-zA-Z][a-zA-Z0-9_-]{0,62}$")
  let duration = @zod.number().finite().min(0).max(120000)
  let legacy_object = object_fields()
  legacy_object["kind"] = @zod.enum_([
    "circle", "rectangle", "text", "equation", "arrow", "numberline",
  ])
  let new_object = object_fields()
  new_object["ref"] = reference
  new_object["kind"] = @zod.enum_([
    "circle", "rectangle", "text", "equation", "path", "arrow", "numberline",
  ])
  let operations = [
    operation("setState", {
      "compositionId": @zod.string(),
      "objectId": @zod.string(),
      "property": @zod.enum_([
        "x", "y", "width", "height", "rotation", "opacity", "visible", "fill", "stroke",
        "strokeWidth", "text", "fontSize", "cornerRadius", "effect",
      ]),
      "value": @zod.union([@zod.number(), @zod.string(), @zod.boolean()]),
    }),
    operation("setTrack", {
      "transitionId": @zod.string(),
      "objectId": @zod.string(),
      "property": @zod.enum_(["type", "start", "duration", "easing", "order"]),
      "value": @zod.union([@zod.number(), @zod.string(), cubic_easing()]),
    }),
    operation("setPropertyTiming", {
      "transitionId": @zod.string(),
      "objectId": @zod.string(),
      "channel": @zod.enum_([
        "position", "opacity", "size", "rotation", "fill", "stroke", "strokeWidth",
        "fontSize", "cornerRadius", "path", "reveal",
      ]),
      "timing": @zod.object({
        "start": @zod.number().finite().min(0),
        "duration": @zod.number().finite().min(0),
        "easing": easing(),
      }).nullable(),
    }),
    operation("setMotionPath", {
      "transitionId": @zod.string(),
      "objectId": @zod.string(),
      "path": bezier.nullable(),
    }),
    operation("setShapePath", {
      "compositionId": @zod.string(),
      "objectId": @zod.string(),
      "path": bezier,
    }),
    operation("setCompositionDuration", {
      "compositionId": @zod.string(),
      "duration": @zod.number(),
    }),
    operation("setTransitionDuration", {
      "transitionId": @zod.string(),
      "duration": @zod.number(),
    }),
    operation("addObject", legacy_object),
    operation("createObject", new_object),
    operation("appendComposition", {
      "ref": reference,
      "transitionRef": reference,
      "name": @zod.string().trim().min(1).max(100),
      "duration": duration,
      "transitionDuration": duration,
    }),
  ]
  let image = {
    "ref": reference,
    "compositionId": @zod.string(),
    "name": @zod.string(),
    "x": @zod.number(),
    "y": @zod.number(),
    "width": @zod.number(),
  }
  if resolved {
    image["height"] = @zod.number()
    image["image"] = image_asset()
    operations.push(operation("createImage", image))
  } else {
    image["prompt"] = @zod.string().trim().min(1).max(1000)
    image["size"] = @zod.enum_(["square", "landscape", "portrait"])
    image["transparent"] = @zod.boolean()
    operations.push(operation("generateImage", image))
  }
  @zod.object({
    "message": @zod.string().max(3000),
    "operations": @zod.array(@zod.discriminated_union("action", operations)).max(
      100,
    ),
  })
}

///|
let edit_proposal_cache : Ref[@zod.ZodSchema?] = Ref(None)

///|
fn edit_proposal() -> @zod.ZodSchema {
  cached_schema(edit_proposal_cache, fn() { proposal_schema(false) })
}

///|
let resolved_proposal_cache : Ref[@zod.ZodSchema?] = Ref(None)

///|
fn resolved_proposal() -> @zod.ZodSchema {
  cached_schema(resolved_proposal_cache, fn() { proposal_schema(true) })
}

///|
pub fn edit_proposal_schema() -> @core.Any {
  edit_proposal().as_any()
}

///|
pub fn resolved_proposal_schema() -> @core.Any {
  resolved_proposal().as_any()
}

///|
pub fn parse_resolved_proposal(input : @core.Any) -> @core.Any {
  parse(resolved_proposal(), input)
}
