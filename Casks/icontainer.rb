cask "icontainer" do
  version "2.0.2"
  sha256 "24caaf1e29065c19165b51506e7225f3084a822ea5a74bf5942ad95491b5bc23"

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
