/// Public invocations enter the same GTK application, including desktop shortcuts.
public enum LinuxCLIAction: Equatable, Sendable {
    case desktop
    case autostart
    case action(LinuxAction)
    case help
    case invalid(String)
}

public enum LinuxActionParser {
    public static func parse(arguments: [String]) -> LinuxCLIAction {
        if arguments.isEmpty { return .desktop }
        if arguments == ["--autostart"] { return .autostart }
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        if arguments.count == 2, arguments[0] == "--action", let action = LinuxAction(rawValue: arguments[1]) {
            return .action(action)
        }
        return .invalid("Use --help for the supported actions.")
    }
}
