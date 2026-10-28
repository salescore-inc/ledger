class Ledger < Formula
  desc "Safe, concurrent JSONL append through Cloud Storage generation preconditions"
  homepage "https://github.com/salescore-inc/ledger"
  version "0.2.0"
  license "MIT"

  on_macos do
    depends_on macos: :sequoia
    on_arm do
      url "https://github.com/salescore-inc/ledger/releases/download/v0.2.0/ledger-v0.2.0-darwin-arm64.tar.gz"
      sha256 "2d1a0e88d2c9e885a3879c739dd09577dd2cc5c6a07654ed7022cb13ff0701e0"
    end
  end
  on_linux do
    on_intel do
      url "https://github.com/salescore-inc/ledger/releases/download/v0.2.0/ledger-v0.2.0-linux-amd64.tar.gz"
      sha256 "acce84a83cf8da2c6600bcbd1c58308b3f88f301e3d80034acfe428d4c7037f5"
    end
  end

  def install
    bin.install "ledger"
  end

  test do
    assert_match "ledger append", shell_output("#{bin}/ledger --help")
  end
end
