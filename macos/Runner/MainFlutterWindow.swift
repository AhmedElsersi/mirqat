import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Matches the channel name in `AdminFilePicker`.
  ///
  /// A native open panel rather than a package: `file_picker` is not on the
  /// approved dependency list (CLAUDE.md A.4), and an `NSOpenPanel` is thirty
  /// lines here. The macOS target exists only for the admin tool, so this
  /// channel cannot reach a phone build either.
  private static let filesChannel = "mirqat/admin_files"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let files = FlutterMethodChannel(
      name: MainFlutterWindow.filesChannel,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    files.setMethodCallHandler { call, result in
      switch call.method {
      case "pickRecording":
        let panel = NSOpenPanel()
        panel.title = "Choose a whole-surah recording"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Anything ffmpeg can read. The list is deliberately wide: a reciter
        // hands over whatever their studio exported, and refusing a .wav
        // because the panel only offered .mp3 would be this tool getting in
        // the way of its own job.
        panel.allowedFileTypes = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma"]

        // Cancel is not a failure: it answers nil and the tool keeps whatever
        // was chosen before.
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      case "pickImage":
        let panel = NSOpenPanel()
        panel.title = "Choose a portrait"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["jpg", "jpeg", "png", "webp"]
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      case "pickLinkFile":
        // A QUL recitation export: one audio address per ayah, for a reciter
        // whose recordings someone else already cut and hosts.
        let panel = NSOpenPanel()
        panel.title = "Choose a file of links (a QUL recitation export)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["json"]
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
