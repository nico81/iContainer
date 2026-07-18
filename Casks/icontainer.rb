cask "icontainer" do
  version "2.2.1"
  sha256 "0156583be88e19779308b61d8c16fe084048750266f174c4244592fba87c764a"

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
