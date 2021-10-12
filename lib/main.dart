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
  late StreamSubscription<AlinesEvent> eventSub;

  Menu? menu;
  late List<MapEntry<int, String>> filteredEntries;
  late bool multiSelect;
  late List<bool> selectedEntries;

  ConnectionPageState() : super();

  @override
  void initState() {
    super.initState();
    connection = AlinesConnection(widget.connInfo);

    eventSub = connection.eventStream().listen((e) {
      if (e is ConnectedEvent) {
        setState(() => connected = true);
      } else if (e is OpenMenuEvent) {
        setState(() {
          menu = e.menu;
          filteredEntries = menu!.entries.asMap().entries.toList();
          multiSelect = false;
        });
      } else if (e is DisconnectEvent) {
        eventSub.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Disconnected: ' + e.message)));
        Navigator.pop(context);
      } else if (e is DestroyedEvent) {
        eventSub.cancel();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(connected ? 'Connection lost' : 'Failed to connect')));
        Navigator.pop(context);
      }
    });
  }

  Widget _menuScreenList() => ListView.builder(
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
              setState(() => selectedEntries[filteredEntries[fidx].key] =
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
                  selectedEntries = List.filled(menu!.entries.length, false);
                  selectedEntries[filteredEntries[fidx].key] = true;
                });
              }
            }
          },
        ),
      );

  Widget _menuScreen() => Scaffold(
        appBar: AppBar(
          title: Text(
              '${menu!.title} (${filteredEntries.length}/${menu!.entries.length})'),
          actions: [
            IconButton(
              icon: const Icon(Icons.power_off),
              onPressed: () {
                eventSub.cancel();
                connection.destroy();
                Navigator.pop(context);
              },
            )
          ],
        ),
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
            Expanded(child: _menuScreenList())
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

  @override
  Widget build(BuildContext context) {
    late Widget w;
    if (!connected) {
      w = Scaffold(
        appBar: AppBar(title: const Text('Connecting...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    } else if (menu != null) {
      w = _menuScreen();
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
  late bool autoConnect;
  late ConnectionInfo connInfo;
  late Future _loadPrefs;

  SettingsPageState() : super() {
    _loadPrefs = loadPrefs();
    _loadPrefs.then((_) {
      if (autoConnect) {
        connect();
      }
    });
  }

  Future savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('autoconnect', autoConnect);
    prefs.setString('conn-addr', connInfo.address);
    prefs.setInt('conn-port', connInfo.port);
    prefs.setString('conn-pass', connInfo.password);
  }

  Future loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    autoConnect = prefs.getBool('autoconnect') ?? false;
    connInfo = ConnectionInfo(
      prefs.getString('conn-addr') ?? '192.168.x.x',
      prefs.getInt('conn-port') ?? 64937,
      prefs.getString('conn-pass') ?? '',
    );
  }

  Future connect() async {
    await savePrefs();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ConnectionPage(connInfo: connInfo),
      ),
    );
  }

  List<Widget> _inputList() => [
        TextFormField(
          decoration: const InputDecoration(hintText: 'Address'),
          initialValue: connInfo.address,
          onChanged: (str) => connInfo.address = str,
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
          onChanged: (str) => connInfo.password = str,
        ),
        Row(
          children: [
            Checkbox(
              value: autoConnect,
              onChanged: (val) => setState(() => autoConnect = val ?? false),
            ),
            GestureDetector(
              onTap: () => setState(() => autoConnect = !autoConnect),
              child: const Text('Autoconnect'),
            ),
          ],
        ),
        TextButton(
          onPressed: () => connect(),
          style: TextButton.styleFrom(
            primary: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 3,
            padding: const EdgeInsets.all(8),
          ),
          child: const Text('Connect'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadPrefs,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Text('Loading...'));
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Connection Settings')),
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: _inputList()),
          ),
        );
      },
    );
  }
}
