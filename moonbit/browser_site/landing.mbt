///|
priv struct LandingView {
  copy : @site.LandingCopy
  locale : @site.Locale
  busy : @site.Template?
  error : String
  resume_url : String?
  start : (@site.Template) -> Unit
  cancel : () -> Unit
}

///|
fn brand(copy : @site.LandingCopy, footer : Bool) -> @react.Element {
  h(
    "a",
    {
      "className": @core.any("landing-brand"),
      "href": @core.any("#top"),
      "aria-label": @core.any(if footer { copy.backToTop } else { copy.home }),
    },
    [
      h(
        "img",
        {
          "src": @core.any("/poietra.svg"),
          "alt": @core.any(""),
          "width": @core.any(if footer { "27" } else { "34" }),
          "height": @core.any(if footer { "27" } else { "34" }),
        },
        [],
      ),
      tag("span", ["Poietra"]),
    ],
  )
}

///|
fn hero(view : LandingView) -> @react.Element {
  let c = view.copy
  let busy = view.busy is Some(_)
  let resume_link = view.resume_url.map(fn(url) {
    anchor("landing-resume", url, [c.resume_label, icon("ArrowRight", 14)])
  })
  let status = view.busy.map(fn(template) {
    cls("div", "landing-launch-status", [
      h("p", { "role": @core.any("status") }, [
        if template == Example {
          c.preparingExample
        } else {
          c.preparingProject
        },
      ]),
      h(
        "button",
        { "autoFocus": @core.any(true), "onClick": @core.any(view.cancel) },
        [c.cancel],
      ),
    ])
  })
  let error = if view.error.is_empty() {
    None
  } else {
    Some(
      h(
        "p",
        {
          "className": @core.any("landing-launch-error"),
          "role": @core.any("alert"),
        },
        [view.error],
      ),
    )
  }
  h(
    "section",
    {
      "className": @core.any("landing-hero landing-container"),
      "aria-labelledby": @core.any("landing-title"),
    },
    [
      cls("p", "landing-eyebrow", [tag("span", []), c.eyebrow]),
      cls("div", "landing-hero-layout", [
        h("h1", { "id": @core.any("landing-title"), "lang": @core.any("en") }, [
          c.title[0],
          linebreak(),
          tag("span", [c.title[1]]),
        ]),
        cls("div", "landing-hero-copy", [
          cls("p", "landing-hero-statement", [lines(c.statement)]),
          tag("p", [c.introduction]),
          h(
            "div",
            {
              "className": @core.any("landing-actions"),
              "aria-busy": @core.any(busy),
            },
            [
              action(
                "landing-button landing-button-primary",
                busy,
                fn() { (view.start)(Blank) },
                [c.newProject, icon("ArrowUpRight", 17)],
              ),
              action(
                "landing-button landing-button-secondary",
                busy,
                fn() { (view.start)(Example) },
                [c.example, icon("ArrowRight", 16)],
              ),
            ],
          ),
          cls("p", "landing-start-note", [c.accountNote]),
          resume_link,
          status,
          error,
        ]),
      ]),
      cls("div", "landing-hero-foot", [
        tag("span", [c.heroNote]),
        anchor("", "#studio", [c.seeStudio, icon("ArrowDown", 14)]),
      ]),
    ],
  )
}

///|
fn product(copy : @site.LandingCopy) -> @react.Element {
  h(
    "section",
    {
      "className": @core.any("landing-product landing-container"),
      "id": @core.any("studio"),
      "aria-label": @core.any(copy.editorLabel),
    },
    [
      tag("figure", [
        cls("div", "landing-product-frame", [
          tag("picture", [
            h(
              "source",
              {
                "type": @core.any("image/webp"),
                "srcSet": @core.any(
                  "/studio-preview-720.webp 720w, /studio-preview-1440.webp 1440w",
                ),
                "sizes": @core.any(
                  "(min-width: 1600px) 1340px, (min-width: 1296px) 1180px, (max-width: 480px) calc(100vw - 50px), (max-width: 1100px) calc(100vw - 84px), calc(100vw - 116px)",
                ),
              },
              [],
            ),
            h(
              "img",
              {
                "src": @core.any("/studio-preview.png"),
                "alt": @core.any(copy.editorAlt),
                "width": @core.any("1440"),
                "height": @core.any("900"),
                "fetchPriority": @core.any("high"),
                "decoding": @core.any("async"),
              },
              [],
            ),
          ]),
        ]),
        tag("figcaption", [
          tag("span", [
            cls("span", "landing-caption-dot", []),
            "Poietra Studio",
            cls("span", "landing-caption-separator", ["/"]),
            copy.editorCaption,
          ]),
          tag("span", [copy.editorNote]),
        ]),
      ]),
    ],
  )
}

///|
fn detail(copy : @site.LandingCopy) -> @react.Element {
  h(
    "section",
    {
      "className": @core.any("landing-detail landing-container"),
      "id": @core.any("features"),
      "aria-labelledby": @core.any("landing-detail-title"),
    },
    [
      cls("div", "landing-section-copy", [
        cls("p", "landing-section-index", [
          "01 ",
          tag("span", [copy.detailEyebrow]),
        ]),
        h("h2", { "id": @core.any("landing-detail-title") }, [
          lines(copy.detailTitle),
        ]),
        tag("p", [lines(copy.detailRhythm)]),
        cls("p", "landing-detail-description", [copy.detailDescription]),
        anchor("landing-inline-link", "#workflow", [
          copy.detailLink,
          icon("ArrowRight", 16),
        ]),
      ]),
      @react.jsx(@core.any(motion_study), [], props={ "copy": @core.any(copy) }),
    ],
  )
}

///|
fn workflow(copy : @site.LandingCopy) -> @react.Element {
  let aside = fn(name : String, size : Int, values : Array[String]) {
    cls("div", "landing-step-aside", [
      icon(name, size),
      tag("span", [values[0], linebreak(), " ", values[1]]),
    ])
  }
  h(
    "section",
    {
      "className": @core.any("landing-workflow"),
      "id": @core.any("workflow"),
      "aria-labelledby": @core.any("landing-workflow-title"),
    },
    [
      cls("div", "landing-container", [
        cls("div", "landing-workflow-heading", [
          cls("p", "landing-section-index", [
            "02 ",
            tag("span", [copy.workflowEyebrow]),
          ]),
          h("h2", { "id": @core.any("landing-workflow-title") }, [
            lines(copy.workflowTitle),
          ]),
          tag("p", [lines(copy.workflowIntroduction)]),
        ]),
        cls("ol", "landing-steps", [
          tag("li", [
            cls("div", "landing-step-number", ["01"]),
            cls("div", "landing-step-copy", [
              tag("h3", [copy.sharingTitle]),
              tag("p", [copy.sharingDescription]),
            ]),
            aside("Link2", 19, copy.sharingAside),
          ]),
          tag("li", [
            cls("div", "landing-step-number", ["02"]),
            cls("div", "landing-step-copy", [
              tag("h3", [copy.aiTitle]),
              tag("p", [
                copy.aiBeforeMention,
                tag("code", ["@codex"]),
                copy.aiAfterMention,
              ]),
            ]),
            h(
              "div",
              {
                "className": @core.any("landing-ai-note"),
                "aria-label": @core.any(copy.aiExampleLabel),
              },
              [
                tag("span", [icon("MessageSquare", 14), copy.aiExampleEyebrow]),
                tag("p", [tag("span", ["@codex"]), " ", copy.aiExample]),
                tag("div", [icon("Check", 13), copy.aiReview]),
              ],
            ),
          ]),
          tag("li", [
            cls("div", "landing-step-number", ["03"]),
            cls("div", "landing-step-copy", [
              tag("h3", [copy.mediaTitle]),
              tag("p", [copy.mediaDescription]),
            ]),
            aside("AudioLines", 22, copy.mediaAside),
          ]),
        ]),
      ]),
    ],
  )
}

///|
fn closing(view : LandingView) -> @react.Element {
  let c = view.copy
  h(
    "section",
    {
      "className": @core.any("landing-closing landing-container"),
      "aria-labelledby": @core.any("landing-closing-title"),
    },
    [
      cls("div", "landing-closing-label", [
        icon("MousePointer2", 18),
        tag("span", [c.closingEyebrow]),
      ]),
      h("h2", { "id": @core.any("landing-closing-title") }, [
        c.closingTitle[0],
        cls("br", "landing-mobile-break", []),
        c.closingTitle[1],
      ]),
      action(
        "landing-button landing-button-primary",
        view.busy is Some(_),
        fn() {
          let title = @core.global_this()
            ._get("document")
            ._call("getElementById", [@core.any("landing-title")])
          if !@core.is_nullish(title) {
            title._call("scrollIntoView", [
              @core.from_entries([("block", @core.any("start"))]),
            ])
            |> ignore
          }
          (view.start)(Blank)
        },
        [c.closingAction, icon("ArrowUpRight", 18)],
      ),
      tag("p", [c.closingNote]),
    ],
  )
}

///|
fn landing(view : LandingView) -> @react.Element {
  let c = view.copy
  h(
    "div",
    {
      "className": @core.any("landing-page"),
      "id": @core.any("top"),
      "lang": @core.any(@site.locale_name(view.locale)),
    },
    [
      anchor("landing-skip", "#landing-main", [c.skip]),
      cls("header", "landing-header landing-container", [
        brand(c, false),
        h("nav", { "aria-label": @core.any(c.navigation) }, [
          cls("div", "landing-nav-links", [
            anchor("", "#studio", [c.studio]),
            anchor("", "#features", [c.features]),
            anchor("", "#workflow", [c.workflow]),
          ]),
          action(
            "landing-nav-start",
            view.busy is Some(_),
            fn() { (view.start)(Blank) },
            [c.start, icon("ArrowUpRight", 16)],
          ),
        ]),
      ]),
      h(
        "main",
        { "id": @core.any("landing-main"), "tabIndex": @core.any(-1) },
        [hero(view), product(c), detail(c), workflow(c), closing(view)],
      ),
      cls("footer", "landing-footer landing-container", [
        brand(c, true),
        tag("p", [c.footerNote]),
        h(
          "a",
          {
            "href": @core.any("https://github.com/Poietra/poietra"),
            "target": @core.any("_blank"),
            "rel": @core.any("noreferrer"),
          },
          ["GitHub", icon("ArrowUpRight", 14)],
        ),
      ]),
    ],
  )
}

///|
pub fn landing_page(input : @core.Any) -> @react.Element {
  let locale = @site.locale(input._get("locale").cast()).unwrap_or(English)
  let busy = optional_string(input._get("busy")).map(fn(value) {
    if value == "example" {
      @site.Example
    } else {
      @site.Blank
    }
  })
  let start : (String) -> Unit = input._get("onStart").cast()
  landing({
    copy: @site.landing_copy(locale),
    locale,
    busy,
    error: input._get("error").cast(),
    resume_url: optional_string(input._get("resumeUrl")),
    start: fn(template) { start(@site.template_name(template)) },
    cancel: input._get("onCancel").cast(),
  })
}
