class Ledger < Formula
  desc "Safe, concurrent JSONL append through Cloud Storage generation preconditions"
  homepage "https://github.com/salescore-inc/ledger"
  version "0.1.0"
  license "MIT"

  on_macos do
    depends_on macos: :sequoia
    on_arm do
      url "https://github.com/salescore-inc/ledger/releases/download/v0.1.0/ledger-v0.1.0-darwin-arm64.tar.gz"
      sha256 "d5a9e1dab968d400a5c7eaab4457dc53692b8d27b42b3929d248c204b7a2bd3a"
    end
  end
  on_linux do
    on_intel do
      url "https://github.com/salescore-inc/ledger/releases/download/v0.1.0/ledger-v0.1.0-linux-amd64.tar.gz"
      sha256 "0392994afe49d9d62ead4e8ec92c8fca83875da755788aee1a2793a0d901b809"
    end
  end

  def install
    bin.install "ledger"
  end

  test do
    assert_match "ledger append", shell_output("#{bin}/ledger --help")
  end
end
