import ArgumentParser

@main
struct Gyro: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gyro",
        abstract: "Read the motion, lid and light sensors built into Apple Silicon MacBooks.",
        discussion: """
            The accelerometer and gyroscope only report to root, so commands that
            read them need sudo. The lid angle sensor works without it.
            """,
        version: "0.1.0",
        subcommands: [Dashboard.self, Stream.self, Lid.self, Sensors.self],
        defaultSubcommand: Dashboard.self
    )
}
