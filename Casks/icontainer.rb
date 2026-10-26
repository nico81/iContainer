cask "icontainer" do
  version "2.6.0"
  sha256 "1b88709403754ed1e07472975a8ccfa88bd36e0c92317e7cde7e58e47e791ee2"

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
