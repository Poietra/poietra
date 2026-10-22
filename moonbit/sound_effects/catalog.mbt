///|
pub(all) enum Voice {
  Click
  Tap
  Pop
  Whoosh
  Swish
  Impact
  Riser
  Chime
  Success
  Glitch
} derive(Eq, Debug)

///|
pub(all) enum SyncPoint {
  Onset
  Peak
  End
} derive(Eq, Debug)

///|
pub(all) struct Preset {
  voice : Voice
  id : String
  name : String
  description : String
  keywords : String
  duration : Double
  sync : SyncPoint
}

///|
/// Original, model-free recipes. Durations and cue times are in milliseconds.
pub fn presets() -> Array[Preset] {
  [
    {
      voice: Whoosh,
      id: "whoosh",
      name: "Whoosh",
      description: "空気が通り抜ける、大きな移動",
      keywords: "移動 スライド 切り替え transition",
      duration: 650.0,
      sync: Peak,
    },
    {
      voice: Swish,
      id: "swish",
      name: "Swish",
      description: "文字やカードを払う、軽い移動",
      keywords: "移動 スライド swipe",
      duration: 280.0,
      sync: Peak,
    },
    {
      voice: Pop,
      id: "pop",
      name: "Pop",
      description: "丸く弾む、アイコンの出現",
      keywords: "出現 ポップ 弾む appear",
      duration: 240.0,
      sync: Onset,
    },
    {
      voice: Click,
      id: "click",
      name: "Click",
      description: "短く明るい、ボタンのクリック",
      keywords: "クリック ボタン tick",
      duration: 110.0,
      sync: Onset,
    },
    {
      voice: Tap,
      id: "tap",
      name: "Tap",
      description: "柔らかな、軽い着地",
      keywords: "タップ 接触 着地 land",
      duration: 230.0,
      sync: Onset,
    },
    {
      voice: Impact,
      id: "impact",
      name: "Impact",
      description: "低く響く、タイトルの着地",
      keywords: "衝突 着地 インパクト hit",
      duration: 850.0,
      sync: Onset,
    },
    {
      voice: Riser,
      id: "riser",
      name: "Riser",
      description: "徐々に高まり、登場の直前に止まる",
      keywords: "盛り上がり 登場 予告 reveal",
      duration: 1100.0,
      sync: End,
    },
    {
      voice: Chime,
      id: "chime",
      name: "Chime",
      description: "澄んだ一音、通知や強調",
      keywords: "通知 ベル 強調 bell",
      duration: 900.0,
      sync: Onset,
    },
    {
      voice: Success,
      id: "success",
      name: "Success",
      description: "三音が重なる、完了の合図",
      keywords: "成功 完了 通知 ロゴ logo",
      duration: 750.0,
      sync: Onset,
    },
    {
      voice: Glitch,
      id: "glitch",
      name: "Glitch",
      description: "細かな断片、デジタルな切り替え",
      keywords: "エラー デジタル 切り替え error",
      duration: 320.0,
      sync: Peak,
    },
  ]
}
