# lives in a separate homebrew-tap repo when published:
#   brew tap gregsadetsky/tap && brew install --cask spacebar
cask "spacebar" do
  version "0.2.1"
  sha256 "ab716efc8f596c9d24789a8d5a30fbbe6b0acce7c4c71b64c13f38d91a90bc2e"

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

  # steps run in homebrew's sandbox: launching the app from here is refused by
  # launch services, so the extension copies its bundled plugins itself on first use.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Spacebar.app"],
                          writable_paths: ["Spacebar.app"], writable_base: :appdir, must_succeed: false
    run "/usr/bin/pluginkit", args: ["-e", "use", "-i", "io.spacebar.app.QuickLook"], must_succeed: false
  end

  caveats <<~EOS
    Unsigned build. If previews don't show up, enable the extension:
      System Settings → General → Login Items & Extensions → Quick Look → Spacebar
    Then press space on a .sqlite3, .geojson, .plist, .md, .ipynb, .zip, .epub or .srt file.
    More plugins can be added; see https://github.com/gregsadetsky/spacebar
  EOS
end
