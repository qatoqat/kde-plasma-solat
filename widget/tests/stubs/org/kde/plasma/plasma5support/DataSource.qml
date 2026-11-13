import QtQuick
import TestHooks

QtObject {
    property string engine
    property var connectedSources: []
    signal newData(string source, var data)
    function connectSource(source) {
        TestHooks.runner = this;
        TestHooks.commands = TestHooks.commands.concat([source]);
    }
    function disconnectSource(source) {}
}
