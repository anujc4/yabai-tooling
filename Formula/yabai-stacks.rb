class YabaiStacks < Formula
  desc "Stack indicators for yabai: app icons for stacked windows, click to focus"
  homepage "https://github.com/anujc4/yabai-tooling"
  url "https://github.com/anujc4/yabai-tooling/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "3984afebfa9f0e91c87cbbdac6ec3f745057166f7ad7dc6128f9d24603446901"
  license "MIT"
  head "https://github.com/anujc4/yabai-tooling.git", branch: "main"

  # Swift 6 and the AppKit APIs this uses need macOS 14 or later, matching
  # Package.swift's platform floor.
  depends_on macos: :sonoma

  def install
    # SwiftPM writes into .build, which Homebrew's sandbox forbids.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/yabai-stacks"
  end

  test do
    assert_match "yabai-stacks", shell_output("#{bin}/yabai-stacks --version")
    assert_match "--icon-size", shell_output("#{bin}/yabai-stacks --help")
    # An unknown flag must fail loudly rather than falling back to defaults.
    assert_match "unknown flag", shell_output("#{bin}/yabai-stacks --nope 2>&1", 1)
  end
end
