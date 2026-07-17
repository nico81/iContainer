cask "icontainer" do
  version "2.1.2"
  sha256 "d870f95c031bc2a44a5365d789c3a480787254dd35b36163fa3bcc008e627a2a"

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
