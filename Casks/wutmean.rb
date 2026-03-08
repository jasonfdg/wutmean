cask "wutmean" do
  version "2.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/jasonfdg/wutmean/releases/download/v#{version}/wutmean-#{version}.zip"
  name "wutmean"
  desc "Select any text, get an instant explanation at three levels"
  homepage "https://github.com/jasonfdg/wutmean"

  depends_on macos: ">= :ventura"

  app "wutmean.app"

  postflight do
    system "mkdir", "-p", "#{Dir.home}/.config/wutmean"
  end

  zap trash: [
    "~/.config/wutmean",
  ]
end
