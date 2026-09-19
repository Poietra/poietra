// Dynamic npm loading only. Conversion, filtering and cache lifetimes are MoonBit.
export async function loadMathRuntime() {
  const [{ mathjax }, { TeX }, { SVG }, { liteAdaptor }, { RegisterHTMLHandler }] = await Promise.all([
    import('mathjax-full/js/mathjax.js'), import('mathjax-full/js/input/tex.js'),
    import('mathjax-full/js/output/svg.js'), import('mathjax-full/js/adaptors/liteAdaptor.js'),
    import('mathjax-full/js/handlers/html.js'), import('mathjax-full/js/input/tex/ams/AmsConfiguration.js'),
  ]);
  return { mathjax, TeX, SVG, liteAdaptor, RegisterHTMLHandler };
}
