cask "moonly" do
  version "0.1.0"
  # Replace with the real DMG checksum from `Scripts/make_dmg.sh`.
  sha256 "dfd3f225968faa9479ec06e7de4f5abb1060b011009303cc49286495a88ac7ea"

  # GitHub Releases caps assets at 2 GB; the app itself is tiny, but host the
  # DMG wherever you like. Hugging Face Hub (LFS) is a good fit here.
  url "https://huggingface.co/datasets/merve/moonly/resolve/v#{version}/Moonly-#{version}.dmg"
  name "Moonly"
  desc "On-device menstrual cycle tracker with local Gemma recommendations"
  homepage "https://github.com/merve/moonly"

  # The engine is shared with the CLI rather than bundled (à la ggml-org's
  # Llama.app). This provides `llama-server`, which the app drives with `-hf`.
  depends_on formula: "llama.cpp"
  depends_on macos: ">= :sonoma"

  app "Moonly.app"

  # Warm the model cache at install time (~5 GB, one time). Best-effort: if it
  # can't finish, the app downloads on first launch. The download is the only
  # outbound traffic Moonly ever makes.
  postflight do
    fetch = "#{appdir}/Moonly.app/Contents/Resources/fetch_model.sh"
    if File.exist?(fetch)
      ohai "Pre-downloading Gemma 4 E4B (QAT) for Moonly — this can take a while."
      system_command "/bin/bash", args: [fetch], print_stdout: true
    end
  end

  uninstall quit: "co.huggingface.moonly"

  # Symptom logs and the cached model both live here; remove on uninstall.
  zap trash: [
    "~/Library/Application Support/Moonly",
  ]
end
