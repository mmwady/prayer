{{flutter_js}}
{{flutter_build_config}}

// Use the renderer packaged in the static build, including when fully offline.
// Keep normal hardware selection; forcing CPU hides decoded evidence on this host.
_flutter.loader.load({config:{canvasKitBaseUrl:new URL('canvaskit/',document.baseURI).href,
  fontFallbackBaseUrl:new URL('assets/assets/fonts/',document.baseURI).href}});
