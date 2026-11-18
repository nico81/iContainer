cask "icontainer" do
  version "2.7.0"
  sha256 "32b7598423398461f2c9b834628ce147c193f9426bbb812f0db63103020e4c9d"

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
