cask "icontainer" do
  version "1.6.0"
  sha256 "0c1586605a655e763ad6ac625ae54bdb5032d7ea2df0838b2bf9187c6d493e4a"

  url "https://github.com/nico81/iContainer/releases/download/v#{version}/iContainer-v#{version}.zip"
  name "iContainer"
  desc "Native macOS UI for Apple's container CLI"
  homepage "https://github.com/nico81/iContainer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "iContainer.app"

  zap trash: [
    "~/Library/Preferences/com.nicoemanuelli.iContainer.plist",
    "~/Library/Saved Application State/com.nicoemanuelli.iContainer.savedState",
  ]
end
