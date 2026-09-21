///|
pub(all) struct Endpoint {
  path : String
  method_ : String
  operation_id : String
  summary : String
}

///|
pub fn endpoints() -> Array[Endpoint] {
  [
    {
      path: "/capabilities",
      method_: "GET",
      operation_id: "poietraCapabilities",
      summary: "Read supported formats, source media and limits",
    },
    {
      path: "/inspect",
      method_: "POST",
      operation_id: "poietraInspect",
      summary: "Validate a portable project and report compatibility",
    },
    {
      path: "/render",
      method_: "POST",
      operation_id: "poietraRender",
      summary: "Render a portable project to SVG, PNG or MP4",
    },
  ]
}

///|
pub fn capabilities() -> Json {
  {
    "formats": Json([@job.Svg, @job.Png, @job.Mp4].map(@job.Format::name)),
    "videoCodec": "avc",
    "audioCodec": "mp3",
    "imageInputs": ["image/png", "image/jpeg"],
    "audioInputs": ["PCM WAV"],
    "videoInputs": false,
    "maxInputBytes": Json(@job.max_input_bytes),
    "maxPixels": Json(@job.max_pixels),
    "maxVideoDurationMs": Json(@job.max_video_duration_ms),
    "maxVideoFrames": Json(@job.max_video_frames),
    "externalAssets": false,
  }
}

///|
pub fn project_schema_json() -> String {
  @codec.project_schema().stringify()
}

///|
pub fn example_json() -> String {
  let scene = @scene.blank_scene("hello", "Hello, agent")
  scene.objects["title"] = {
    id: "title",
    name: "Greeting",
    kind: @scene.Text,
    order: 0.0,
    groupId: None,
    parentId: None,
    locked: false,
    image: None,
    media: None,
    playback: None,
  }
  scene.compositions["hello-comp-1"].states["title"] = {
    ..@scene.default_state(@scene.Text),
    x: 640.0,
    y: 360.0,
    text: "Hello, agent.",
    fontSize: 72.0,
    fill: "#ffffff",
    strokeWidth: 0.0,
  }
  let project : @scene.Project = {
    version: 2,
    name: "Hello, agent",
    sceneOrder: ["hello"],
    scenes: { "hello": scene },
  }
  @core.json_stringify(@codec.encode_Project(project))
}

///|
fn parameter(name : String, schema : Json, description : String) -> Json {
  {
    "name": Json(name),
    "in": "query",
    "required": false,
    "description": Json(description),
    "schema": schema,
  }
}

///|
fn error_response(description : String) -> Json {
  {
    "description": Json(description),
    "content": {
      "application/json": { "schema": { "$ref": "#/components/schemas/Error" } },
    },
  }
}

///|
pub fn openapi_json(server_url : String) -> String {
  let paths : Map[String, Json] = Map([])
  for endpoint in endpoints() {
    let responses : Map[String, Json] = {
      "401": error_response("Missing or incorrect bearer token."),
      "403": error_response("Disallowed Origin or Host."),
      "500": error_response("Unexpected transport failure."),
    }
    let operation : Map[String, Json] = {
      "operationId": Json(endpoint.operation_id),
      "summary": Json(endpoint.summary),
      "tags": ["Rendering"],
    }
    if endpoint.method_ == "POST" {
      operation["requestBody"] = {
        "required": true,
        "description": "The complete portable project, directly as JSON, with embedded PNG/JPEG and PCM WAV. Maximum 32 MiB. This endpoint does not accept a URL, multipart upload or {project: ...} wrapper.",
        "content": {
          "application/json": {
            "schema": { "$ref": "#/components/schemas/Project" },
            "examples": {
              "hello": {
                "summary": "One second of editable text at 1280x720",
                "externalValue": "https://poietra.com/examples/hello.poietra.json",
              },
            },
          },
        },
      }
      responses["400"] = error_response(
        "Unknown, empty or repeated query parameter.",
      )
      responses["413"] = error_response("Input exceeds 32 MiB.")
      responses["415"] = error_response(
        "Content-Type must be application/json.",
      )
      responses["422"] = error_response(
        "Invalid project/options, unsupported media or render failure.",
      )
      responses["429"] = error_response(
        "Another inspect/render request is running. Retry after completion.",
      )
    }
    if endpoint.path == "/render" {
      operation["description"] = "Waits for completion and returns raw file bytes. No job ID or persistent result URL. A disconnect cancels the job. The default timeout is 120 seconds. MP4 is H.264 with MP3 when audio is present; source video, compressed audio, WebP and external assets are unsupported."
      operation["parameters"] = [
        parameter(
          "format",
          { "type": "string", "enum": ["svg", "png", "mp4"], "default": "png" },
          "Output format.",
        ),
        parameter(
          "width",
          { "type": "integer", "minimum": 1, "maximum": 1920 },
          "Output width. MP4 dimensions must be even; total pixels must not exceed 2,073,600. A single supplied dimension preserves aspect ratio.",
        ),
        parameter(
          "height",
          { "type": "integer", "minimum": 1, "maximum": 1920 },
          "Output height. Same dimension constraints as width.",
        ),
        parameter(
          "fps",
          { "type": "integer", "enum": [24, 30, 60], "default": 30 },
          "Frame rate. MP4 is limited to 60 seconds and 1800 frames, whichever is reached first.",
        ),
        parameter(
          "timeMs",
          { "type": "number", "minimum": 0, "default": 0 },
          "Project time for SVG/PNG, inside the project duration. MP4 requires zero.",
        ),
      ]
      responses["200"] = {
        "description": "Complete output file as binary (SVG is UTF-8 XML).",
        "headers": {
          "Content-Disposition": {
            "schema": { "type": "string" },
            "description": "Attachment filename.",
          },
          "X-Poietra-Frames": {
            "schema": { "type": "integer", "minimum": 0 },
            "description": "Encoded video frames; zero for still output.",
          },
          "X-Poietra-Rasterized-Frames": {
            "schema": { "type": "integer", "minimum": 0 },
            "description": "Rasterized frames, excluding reused static holds.",
          },
          "X-Poietra-Duration-Ms": {
            "schema": { "type": "number", "minimum": 0 },
            "description": "Authored duration; zero for still output.",
          },
        },
        "content": { "image/svg+xml": {}, "image/png": {}, "video/mp4": {} },
      }
      responses["504"] = error_response("Rendering exceeded its time limit.")
    } else {
      let schema = if endpoint.path == "/inspect" {
        "Inspection"
      } else {
        "Capabilities"
      }
      responses["200"] = {
        "description": Json(endpoint.summary),
        "content": {
          "application/json": {
            "schema": { "$ref": Json("#/components/schemas/" + schema) },
          },
        },
      }
      if endpoint.path == "/inspect" {
        operation["description"] = "Validates document structure, references and timing, and reports known unsupported source types. An empty issues list does not guarantee that embedded media will decode during rendering. Inspection does not encode frames."
      }
    }
    operation["responses"] = Json(responses)
    paths[endpoint.path] = Json(
      Map([(endpoint.method_.to_lower(), Json(operation))]),
    )
  }
  let capability_properties : Map[String, Json] = Map([])
  let required = []
  if capabilities() is Object(values) {
    for key, value in values {
      capability_properties[key] = { "const": value }
      required.push(key)
    }
  }
  let document : Json = {
    "openapi": "3.1.1",
    "info": {
      "title": "Poietra Render API",
      "version": "0.1.0",
      "description": "Render portable Poietra projects with a self-hosted Node 24 service. The public poietra.com site distributes documentation; it is not a hosted render endpoint. Run pnpm render:api from the source checkout. Rendering uses standalone WASM with no Chromium or FFmpeg.",
    },
    "servers": [
      {
        "url": Json(server_url),
        "description": "Your running Poietra render service. The default is local-only.",
      },
    ],
    "externalDocs": {
      "url": "https://poietra.com/developers/",
      "description": "Setup, MCP and working examples",
    },
    "security": [{}, { "renderToken": [] }],
    "tags": [
      {
        "name": "Rendering",
        "description": "Stateless file-to-result rendering",
      },
    ],
    "paths": Json(paths),
    "components": {
      "securitySchemes": {
        "renderToken": {
          "type": "http",
          "scheme": "bearer",
          "description": "POIETRA_RENDER_TOKEN. Required whenever configured; binding outside loopback requires a token. Unconfigured loopback accepts unauthenticated requests.",
        },
      },
      "schemas": {
        "Project": @codec.project_schema(
          reference_prefix="#/components/schemas/Project/$defs/",
        ),
        "Error": {
          "type": "object",
          "required": ["error"],
          "properties": { "error": { "type": "string" } },
        },
        "Capabilities": {
          "type": "object",
          "properties": Json(capability_properties),
          "required": Json(required),
        },
        "Inspection": {
          "type": "object",
          "required": [
            "name", "scenes", "durationMs", "width", "height", "audibleTracks", "issues",
            "capabilities",
          ],
          "properties": {
            "name": { "type": "string" },
            "scenes": { "type": "integer", "minimum": 1 },
            "durationMs": { "type": "number", "minimum": 0 },
            "width": { "type": "number", "minimum": 1 },
            "height": { "type": "number", "minimum": 1 },
            "audibleTracks": { "type": "integer", "minimum": 0 },
            "issues": { "type": "array", "items": { "type": "string" } },
            "capabilities": { "$ref": "#/components/schemas/Capabilities" },
          },
        },
      },
    },
  }
  document.stringify()
}
