final _memory = <String, String>{};

/// Small per-device settings (remembered colours and the like). Outside the
/// browser they last only for the session.
String? localRead(String key) => _memory[key];

void localWrite(String key, String value) => _memory[key] = value;
