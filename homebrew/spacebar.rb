# lives in a separate homebrew-tap repo when published:
#   brew tap gregsadetsky/tap && brew install --cask spacebar
cask "spacebar" do
  version "0.2.3"
  sha256 "c702ef445e912929f42bf5f664266608ab1a731a4151703ff2ded58582368d74"

  url "https://github.com/gregsadetsky/spacebar/releases/download/v#{version}/Spacebar-#{version}.zip"
  name "Spacebar"
  desc "Plugin-based Quick Look previews (GeoJSON, SQLite, …)"
  homepage "https://github.com/gregsadetsky/spacebar"

  app "Spacebar.app"

  uninstall quit: "io.spacebar.app"

  zap trash: [
    "~/Library/Containers/io.spacebar.app.QuickLook",
    "~/Library/Containers/io.spacebar.app",
  ]

  # steps run in homebrew's sandbox: launching the app, lsregister and pluginkit
  # are all refused from here, so the user opens the app once to register the
  # quick look extension (see caveats).
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Spacebar.app"],
                          writable_paths: ["Spacebar.app"], writable_base: :appdir, must_succeed: false
  end

  caveats <<~EOS
    One more step: open Spacebar once so macOS registers the Quick Look extension:
      open -a Spacebar
    Then press space on a .sqlite3, .geojson, .plist, .md, .ipynb, .zip, .epub or .srt file in Finder.
    Unsigned build. If previews still don't show, enable the extension:
      System Settings → General → Login Items & Extensions → Quick Look → Spacebar
    More plugins: https://github.com/gregsadetsky/spacebar
  EOS
end
