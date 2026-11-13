pragma Singleton
import QtQuick

// Shared recorder between the stub Plasma modules and the test driver.
QtObject {
    property var commands: []        // every shell command the widget asked the executable engine to run
    property var notifications: []   // every Notification the widget sent
    property var runner: null        // the widget's DataSource instance
    function reset() { commands = []; notifications = []; runner = null; }
    // Commands issued so far that contain `text`.
    function cmds(text) { return commands.filter(c => c.indexOf(text) >= 0); }
    // Pretend the shell finished `source` with this output.
    function reply(source, stdout, code) {
        runner.newData(source, { "exit code": code === undefined ? 0 : code, "stdout": stdout, "stderr": "" });
    }
}
