cask "icontainer" do
  version "2.1.0"
  sha256 "189a50f6404a7764fadfaf5f235735e194bf4ffe6307089a17fbcfc513a03f1c"

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
