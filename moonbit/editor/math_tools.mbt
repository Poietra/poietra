///|
pub(all) struct MathTool {
  kind : @scene.ObjectKind
  category : String
  label : String
  description : String
  icon : String
}

///|
/// Creation entries are independent of the top-level toolbar. New mathematical
/// families join this catalog; presets reuse a family's semantic data.
pub fn math_tools() -> Array[MathTool] {
  [
    {
      kind: Equation,
      category: "数式",
      label: "数式",
      description: "LaTeXで数式やベクトルの記号を表示",
      icon: "Sigma",
    },
    {
      kind: Graph,
      category: "曲線",
      label: "数式グラフ",
      description: "関数・陰関数の式と係数を編集",
      icon: "ChartSpline",
    },
    {
      kind: Geometry,
      category: "幾何",
      label: "幾何の図",
      description: "点・ベクトル・中点・角度を参照でつなぐ",
      icon: "Triangle",
    },
    {
      kind: NumberLine,
      category: "座標",
      label: "数直線",
      description: "目盛りのある数直線を描く",
      icon: "Minus",
    },
  ]
}
