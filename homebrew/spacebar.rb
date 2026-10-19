# lives in a separate homebrew-tap repo when published:
#   brew tap gregsadetsky/tap && brew install --cask spacebar
cask "spacebar" do
  version "0.1.1"
  sha256 "269d9f3ee924d82b04ea60307d58d0ac7ee3e66a786aa496b0016fe9badc59f2"

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
    Then press space on a .geojson or .sqlite3 file.
  EOS
end
