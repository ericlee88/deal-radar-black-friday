{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/"
  },
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      canvasKitBaseUrl: "canvaskit/"
    });
    const loader = document.getElementById("boot-loader");
    if (loader) {
      loader.style.opacity = "0";
      setTimeout(() => loader.remove(), 260);
    }
    await appRunner.runApp();
  }
});
