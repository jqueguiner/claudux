class Claudux < Formula
  desc "Claude API usage monitor for your tmux status bar"
  homepage "https://github.com/jqueguiner/claudux"
  url "https://github.com/jqueguiner/claudux/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "4521f69957f641708a26f2e05de2ba9048d241de5f6a61544d480879f4482a24"
  license "MIT"

  depends_on "bash"
  depends_on "jq"
  depends_on "curl"
  depends_on "tmux"

  def install
    # Install scripts and config to share/claudux
    (share/"claudux").install "claudux.tmux"
    (share/"claudux/scripts").install Dir["scripts/*"]
    (share/"claudux/config").install Dir["config/*"]

    # Make all scripts executable
    (share/"claudux/scripts").each_child { |f| f.chmod 0755 if f.file? }
    (share/"claudux/claudux.tmux").chmod 0755

    # Install CLI tool
    bin.install "bin/claudux-setup"

    # Install man page
    man1.install "man/claudux.1"
  end

  def post_install
    system "#{bin}/claudux-setup", "install"
    if File.exist?("#{ENV["HOME"]}/.tmux.conf") && system("tmux", "list-sessions", [:out, :err] => "/dev/null")
      system "tmux", "source-file", "#{ENV["HOME"]}/.tmux.conf"
    end
  end

  def caveats
    <<~EOS
      claudux has been added to ~/.tmux.conf automatically.

      If tmux was not running, reload manually:
        tmux source-file ~/.tmux.conf

      For Claude Code subscribers (local mode):
        No configuration needed — claudux reads ~/.claude/ session logs.

      For Anthropic API users (org mode):
        export ANTHROPIC_ADMIN_API_KEY=sk-ant-admin-...
    EOS
  end

  test do
    assert_match "claudux-setup", shell_output("#{bin}/claudux-setup help")
    assert_predicate share/"claudux/claudux.tmux", :exist?
    assert_predicate share/"claudux/scripts/claudux.sh", :exist?
  end
end
