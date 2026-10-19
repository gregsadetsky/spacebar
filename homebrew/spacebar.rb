# lives in a separate homebrew-tap repo when published:
#   brew tap gregsadetsky/tap && brew install --cask spacebar
cask "spacebar" do
  version "0.2.0"
  sha256 "034f3164ecd824e5d295fea13b6257f161ef29a69c90a2526d60a69cdf4c153a"

  url "https://github.com/gregsadetsky/spacebar/releases/download/v#{version}/Spacebar-#{version}.zip"
  name "Spacebar"
  desc "Plugin-based Quick Look previews (GeoJSON, SQLite, …)"
  homepage "https://github.com/gregsadetsky/spacebar"

  app "Spacebar.app"

  zap trash: [
    "~/Library/Containers/io.spacebar.app.QuickLook",
    "~/Library/Containers/io.spacebar.app",
  ]

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Spacebar.app"]
    system_command "/usr/bin/open", args: ["-a", "#{appdir}/Spacebar.app"]
    system_command "/usr/bin/pluginkit", args: ["-e", "use", "-i", "io.spacebar.app.QuickLook"], must_succeed: false
  end

  caveats <<~EOS
    Unsigned build. If previews don't show up, enable the extension:
      System Settings → General → Login Items & Extensions → Quick Look → Spacebar
    Then press space on a .sqlite3, .geojson, .plist, .md, .ipynb, .zip, .epub or .srt file.
    More plugins can be added; see https://github.com/gregsadetsky/spacebar
  EOS
end
