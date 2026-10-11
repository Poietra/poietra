///|
priv struct SelectChoice {
  value : String
  label : String
  disabled : Bool
}

///|
fn select_choice(
  value : String,
  label : String,
  disabled? : Bool = false,
) -> SelectChoice {
  { value, label, disabled, }
}

///|
fn select_input(
  label : String,
  value : String,
  on_change : (String) -> Unit,
  choices : Array[SelectChoice],
  disabled? : Bool = false,
  class_name? : String = "",
  description? : String? = None,
) -> @react.Element {
  let labels : Map[String, @core.Any] = Map([])
  let options : Array[&@react.ReactNode] = []
  for choice in choices {
    labels[choice.value] = @core.any(choice.label)
    options.push(
      ui(
        "Select",
        "Item",
        {
          "key": @core.any(choice.value),
          "value": @core.any(choice.value),
          "data-value": @core.any(choice.value),
          "label": @core.any(choice.label),
          "disabled": @core.any(choice.disabled),
          "className": @core.any("property-select-option"),
        },
        [
          ui(
            "Select",
            "ItemIndicator",
            { "className": @core.any("property-select-check") },
            [icon("Check", 13)],
          ),
          ui("Select", "ItemText", Map([]), [choice.label]),
        ],
      ),
    )
  }
  ui(
    "Select",
    "Root",
    {
      "value": @core.any(value),
      "items": host_record(labels),
      "disabled": @core.any(disabled),
      "onValueChange": @core.any(fn(next : @core.Any) {
        if disabled || @core.is_nullish(next) {
          return
        }
        let next : String = next.cast()
        if choices.any(fn(choice) { choice.value == next && !choice.disabled }) {
          on_change(next)
        }
      }),
    },
    [
      ui(
        "Select",
        "Trigger",
        {
          "aria-label": @core.any(label),
          "aria-describedby": match description {
            Some(id) => @core.any(id)
            None => @core.undefined()
          },
          "data-value": @core.any(value),
          "title": labels.get(value).unwrap_or(@core.any(value)),
          "className": classes([
            @core.any("property-select"),
            @core.any(class_name),
          ]),
        },
        [
          ui(
            "Select",
            "Value",
            { "className": @core.any("property-select-value") },
            [],
          ),
          ui("Select", "Icon", Map([]), [icon("ChevronDown", 13)]),
        ],
      ),
      ui("Select", "Portal", Map([]), [
        ui(
          "Select",
          "Positioner",
          {
            // Rebuild the indexed item registry when choices change. Removing
            // Mixed must not reconcile the new value against shifted indices.
            "key": @core.any(
              choices
              .map(fn(choice) { "\{choice.value.length()}:\{choice.value}" })
              .join(""),
            ),
            "side": @core.any("bottom"),
            "align": @core.any("end"),
            "sideOffset": @core.any(6),
            "alignItemWithTrigger": @core.any(false),
            "className": @core.any("property-select-positioner"),
          },
          [
            ui(
              "Select",
              "Popup",
              { "className": @core.any("property-select-popup") },
              [ui("Select", "List", Map([]), options)],
            ),
          ],
        ),
      ]),
    ],
  )
}
