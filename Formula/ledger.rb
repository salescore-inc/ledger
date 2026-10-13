class Ledger < Formula
  desc "Safe, concurrent JSONL append through Cloud Storage generation preconditions"
  homepage "https://github.com/salescore-inc/ledger"
  version "0.1.1"
  license "MIT"

  on_macos do
    depends_on macos: :sequoia
    on_arm do
      url "https://github.com/salescore-inc/ledger/releases/download/v0.1.1/ledger-v0.1.1-darwin-arm64.tar.gz"
      sha256 "b2fdd59166e95fda481e1f11ee93f7f17a578044643a7a249982ad020638ac5a"
    end
  end
  on_linux do
    on_intel do
      url "https://github.com/salescore-inc/ledger/releases/download/v0.1.1/ledger-v0.1.1-linux-amd64.tar.gz"
      sha256 "3b4dc89a2e1733d85836bc4078b55164a81c7a88cb0dc80c78f906b768bcf0c3"
    end
  end

  def install
    bin.install "ledger"
  end

  test do
    assert_match "ledger append", shell_output("#{bin}/ledger --help")
  end
end
