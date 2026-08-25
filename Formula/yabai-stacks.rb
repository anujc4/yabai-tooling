class YabaiStacks < Formula
  desc "Stack indicators for yabai: app icons for stacked windows, click to focus"
  homepage "https://github.com/anujc4/yabai-tooling"
  url "https://github.com/anujc4/yabai-tooling/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "d6ab9897a02f0ab70dd6ff257af85de5df35494d2c5a4e172d4c724cf5d29be9"
  license "MIT"
  head "https://github.com/anujc4/yabai-tooling.git", branch: "main"

  # Swift 6 and the AppKit APIs this uses need macOS 14 or later, matching
  # Package.swift's platform floor.
  depends_on macos: :sonoma
  depends_on :macos

  def install
    # SwiftPM writes into .build, which Homebrew's sandbox forbids.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/yabai-stacks"
  end

  def caveats
    <<~EOS
      yabai-stacks runs alongside yabai. Add it to ~/.config/yabai/yabairc,
      next to borders, and reload yabai:

        yabai-stacks --icon-size 32 --position right &

      It registers the yabai signals it needs at startup and removes them on
      exit, so no signal configuration is required.
    EOS
  end

  test do
    assert_match "yabai-stacks", shell_output("#{bin}/yabai-stacks --version")
    assert_match "--icon-size", shell_output("#{bin}/yabai-stacks --help")
    # An unknown flag must fail loudly rather than falling back to defaults.
    assert_match "unknown flag", shell_output("#{bin}/yabai-stacks --nope 2>&1", 1)
  end
end
