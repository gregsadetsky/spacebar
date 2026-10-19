# lives in a separate homebrew-tap repo when published:
#   brew tap <you>/tap && brew install --cask spacebar
cask "spacebar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_dist/Spacebar-0.1.0.zip.sha256"

  url "https://github.com/<you>/spacebar/releases/download/v#{version}/Spacebar-#{version}.zip"
  name "Spacebar"
  desc "Plugin-based Quick Look previews (GeoJSON, SQLite, …)"
  homepage "https://github.com/<you>/spacebar"

  app "Spacebar.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Spacebar.app"]
    system_command "/usr/bin/open", args: ["-a", "#{appdir}/Spacebar.app"]
    system_command "/usr/bin/pluginkit", args: ["-e", "use", "-i", "io.spacebar.app.QuickLook"], must_succeed: false
  end

  caveats <<~EOS
    Unsigned build. If previews don't show up, enable the extension:
      System Settings → General → Login Items & Extensions → Quick Look → Spacebar
    Then press space on a .geojson or .sqlite3 file.
  EOS
end
