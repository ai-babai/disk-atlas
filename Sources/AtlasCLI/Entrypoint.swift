import ArgumentParser
import Darwin
import Foundation

let cliVersion = "0.9.0"

@main struct CLIEntrypoint {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)

        do {
            var command = try AtlasCommand.parseAsRoot()
            if var asynchronous = command as? AsyncParsableCommand {
                try await asynchronous.run()
            } else {
                try command.run()
            }
        } catch {
            let code = AtlasCommand.exitCode(for: error).rawValue
            if code == 0 {
                print(AtlasCommand.fullMessage(for: error))
            } else {
                CLIOutput.failure(error, parserCode: code)
            }
            exit(code == 0 ? 0 : CLIOutput.exitStatus(error, parserCode: code))
        }

    }
}
