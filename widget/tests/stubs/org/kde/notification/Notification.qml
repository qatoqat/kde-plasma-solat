import QtQuick
import TestHooks

QtObject {
    enum Flag { Persistent = 1 }
    property string componentName
    property string eventId
    property string iconName
    property string title
    property string text
    property int flags
    property list<QtObject> actions
    property bool closed: false
    function sendEvent() { TestHooks.notifications = TestHooks.notifications.concat([this]); }
    function close() { closed = true; }
}
