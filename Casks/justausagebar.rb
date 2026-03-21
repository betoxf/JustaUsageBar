cask "justausagebar" do
  version "1.0.0"
  sha256 "3b530fb45a5489280c70cf0d7af31e902c6366b0e1810a867c729ec17d9e0578"

  url "https://github.com/betoxf/JustaUsageBar/releases/download/v#{version}/JustaUsageBar.zip"
  name "Just A Usage Bar"
  desc "Menu bar app showing Claude and Codex usage statistics"
  homepage "https://github.com/betoxf/JustaUsageBar"

  depends_on macos: ">= :sonoma"

  app "JustaUsageBar.app"

  postflight do
    # Remove quarantine flag so Gatekeeper doesn't block the unsigned app
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/JustaUsageBar.app"]
    # Launch the app immediately after install
    system_command "/usr/bin/open",
                   args: ["-a", "#{appdir}/JustaUsageBar.app"]
  end

  zap trash: [
    "~/Library/Application Support/JustaUsageBar",
    "~/Library/Preferences/bullfigherstudios.JustaUsageBar.plist",
    "~/Library/Caches/bullfightertudios.JustaUsageBar",
  ]
end
