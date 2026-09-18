cask "icontainer" do
  version "2.4.0"
  sha256 "b34b876fbbea56c09d75ef9a59338654149d3c3ffd378ce761b010943fcaa085"

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
