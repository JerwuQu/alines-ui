import 'dart:async';

import 'package:alines/alines_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AlinesApp());
}

class AlinesApp extends StatelessWidget {
  const AlinesApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'alines',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SettingsPage(),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Loading...'));
  }
}

class MenuWidget extends StatelessWidget {
  const MenuWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Menu!'));
  }
}

class ConnectionPage extends StatefulWidget {
  final ConnectionInfo connInfo;

  const ConnectionPage({required this.connInfo, Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => ConnectionPageState();
}

class ConnectionPageState extends State<ConnectionPage> {
  late AlinesConnection connection;
  bool connected = false;

  Menu? menu;
  late List<MapEntry<int, String>> filteredEntries;
  late bool multiSelect;
  late List<bool> selectedEntries;

  ConnectionPageState() : super();

  @override
  void initState() {
    super.initState();
    connection = AlinesConnection(widget.connInfo);

    late StreamSubscription<AlinesEvent> sub;
    sub = connection.eventStream().listen((e) {
      if (e is ConnectedEvent) {
        setState(() => connected = true);
      } else if (e is OpenMenuEvent) {
        setState(() {
          menu = e.menu;
          filteredEntries = menu!.entries.asMap().entries.toList();
          multiSelect = false;
        });
      } else if (e is CloseMenuEvent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Host closed menu')));
        setState(() => menu = null);
      } else if (e is DisconnectEvent) {
        sub.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Disconnected: ' + e.message)));
        Navigator.pop(context);
      } else if (e is DestroyedEvent) {
        sub.cancel();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(connected ? 'Connection lost' : 'Failed to connect')));
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    late Widget w;
    if (!connected) {
      w = Scaffold(
        appBar: AppBar(title: const Text('Connecting...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    } else if (menu != null) {
      w = Scaffold(
        appBar: AppBar(
            title: Text(
                '${menu!.title} (${filteredEntries.length}/${menu!.entries.length})')),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              child: TextFormField(
                decoration: InputDecoration(
                    hintText:
                        menu!.customEntry ? 'Filter / Custom Entry' : 'Filter'),
                onChanged: (str) {
                  var lowerStr = str.toLowerCase();
                  var newFilteredEntries = menu!.entries
                      .asMap()
                      .entries
                      .where((e) => e.value.toLowerCase().contains(lowerStr))
                      .toList();
                  setState(() => filteredEntries = newFilteredEntries);
                },
                onFieldSubmitted: menu!.customEntry
                    ? (str) {
                        connection.customEntry(str);
                        setState(() => menu = null);
                      }
                    : null,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredEntries.length,
                itemBuilder: (context, fidx) => ListTile(
                  title: Text(filteredEntries[fidx].value),
                  leading: multiSelect
                      ? Icon(
                          selectedEntries[filteredEntries[fidx].key]
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 30.0,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    if (multiSelect) {
                      setState(() =>
                          selectedEntries[filteredEntries[fidx].key] =
                              !selectedEntries[filteredEntries[fidx].key]);
                    } else {
                      connection.selectSingleEntry(filteredEntries[fidx].key);
                      setState(() => menu = null);
                    }
                  },
                  onLongPress: () {
                    if (menu!.multipleChoice) {
                      if (multiSelect) {
                        setState(() => multiSelect = false);
                      } else {
                        setState(() {
                          multiSelect = true;
                          selectedEntries =
                              List.filled(menu!.entries.length, false);
                          selectedEntries[filteredEntries[fidx].key] = true;
                        });
                      }
                    }
                  },
                ),
              ),
            )
          ],
        ),
        floatingActionButton: multiSelect
            ? FloatingActionButton(
                child: const Icon(Icons.send),
                onPressed: () {
                  var selectedEntriesList = selectedEntries
                      .asMap()
                      .entries
                      .where((el) => el.value)
                      .map((el) => el.key)
                      .toList();
                  connection.selectMultipleEntries(selectedEntriesList);
                  setState(() => menu = null);
                },
              )
            : null,
      );
    } else {
      return Scaffold(
        appBar: AppBar(title: const Text('Waiting for menu...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      child: w,
      onWillPop: () async {
        if (menu == null) {
          connection.destroy();
          return true;
        } else {
          connection.closeMenu();
          setState(() => menu = null);
          return false;
        }
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  late ConnectionInfo connInfo;
  late Future<void> _loadPrefs;

  SettingsPageState() : super() {
    _loadPrefs = loadPrefs();
  }

  Future<void> savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('conn-addr', connInfo.address);
    prefs.setInt('conn-port', connInfo.port);
    prefs.setString('conn-pass', connInfo.password);
  }

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    connInfo = ConnectionInfo(
      prefs.getString('conn-addr') ?? '192.168.x.x',
      prefs.getInt('conn-port') ?? 64937,
      prefs.getString('conn-pass') ?? '',
    );
  }

  Future<void> connect() async {
    await savePrefs();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ConnectionPage(connInfo: connInfo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
        future: _loadPrefs,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Loading();
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Connection Settings')),
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Address'),
                    initialValue: connInfo.address,
                    onChanged: (str) => {connInfo.address = str},
                  ),
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Port'),
                    keyboardType: TextInputType.number,
                    initialValue: connInfo.port.toString(),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (str) => connInfo.port = int.tryParse(str) ?? 0,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Password'),
                    initialValue: connInfo.password,
                    onChanged: (str) => {connInfo.password = str},
                  ),
                  // TODO: option to automatically connect on app launch
                  TextButton(
                    onPressed: () => {connect()},
                    style: TextButton.styleFrom(
                      primary: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      elevation: 3,
                      padding: const EdgeInsets.all(8),
                    ),
                    child: const Text('Connect'),
                  ),
                ],
              ),
            ),
          );
        });
  }
}
