cask "justausagebar" do
  version "1.0.0"
  sha256 "d7b8b475c2edcec4383e03a8055071d9552a587da1acb501124221e0ffef9590"

  url "https://github.com/betoxf/JustaUsageBar/releases/download/v#{version}/JustaUsageBar.zip"
  name "Just A Usage Bar"
  desc "Menu bar app showing Claude and Codex usage statistics"
  homepage "https://github.com/betoxf/JustaUsageBar"

  depends_on macos: ">= :sonoma"

  app "JustaUsageBar.app"

  postflight do
    # Ensure the app is registered for launch services
    system_command "/usr/bin/open", args: ["-g", "-a", "#{appdir}/JustaUsageBar.app", "--args", "--background"]
  end

  zap trash: [
    "~/Library/Application Support/JustaUsageBar",
    "~/Library/Preferences/bullfigherstudios.JustaUsageBar.plist",
    "~/Library/Caches/bullfigherstudios.JustaUsageBar",
  ]
end
