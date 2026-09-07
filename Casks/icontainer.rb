cask "icontainer" do
  version "2.3.0"
  sha256 "41b67cd47c51acd5efd352d2c4b4510dcdeee4c10bab6037184ba3585dab121d"

  url "https://github.com/nico81/iContainer/releases/download/v#{version}/iContainer-v#{version}.dmg"
  name "iContainer"
  desc "Native macOS UI for Apple's container CLI"
  homepage "https://github.com/nico81/iContainer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe
  depends_on arch: :arm64

  auto_updates true

  app "iContainer.app"

  zap trash: [
    "~/Library/Preferences/com.nicoemanuelli.iContainer.plist",
    "~/Library/Saved Application State/com.nicoemanuelli.iContainer.savedState",
  ]
end
