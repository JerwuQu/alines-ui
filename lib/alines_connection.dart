import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:async/async.dart';

class ConnectionInfo {
  String address, password;
  int port;
  ConnectionInfo(this.address, this.port, this.password);
}

class OutgoingPacket {
  List<int> data = List.empty(growable: true);

  OutgoingPacket();

  addU8(int n) {
    data.add(n);
  }

  addU16(int n) {
    data.add((n / 256).floor());
    data.add(n % 256);
  }

  addString(String str) {
    List<int> bytes = utf8.encode(str);
    addU16(bytes.length);
    data.addAll(bytes);
  }

  send(Socket sock) {
    sock.add(data);
    sock.flush();
  }
}

class Menu {
  final String title;
  final List<String> entries;
  late bool multipleChoice, customEntry;
  Menu(this.title, this.entries, int flags) {
    multipleChoice = (flags & 1) > 0;
    customEntry = (flags & 2) > 0;
  }
}

class AlinesEvent {}

class ConnectedEvent implements AlinesEvent {}

class OpenMenuEvent implements AlinesEvent {
  final Menu menu;
  OpenMenuEvent(this.menu);
}

class CloseMenuEvent implements AlinesEvent {}

class DisconnectEvent implements AlinesEvent {
  final String message;
  DisconnectEvent(this.message);
}

class DestroyedEvent implements AlinesEvent {}

class AlinesConnection {
  final ConnectionInfo info;
  final StreamController<AlinesEvent> _eventStream = StreamController();
  final StreamController<int> _dataStream = StreamController<int>();
  late StreamQueue<int> _byteQueue;

  bool _connected = false;
  bool _destroyed = false;
  late Socket _socket;

  AlinesConnection(this.info) {
    Socket.connect(info.address, info.port).then((socket) {
      if (_destroyed) {
        socket.destroy();
        return;
      }

      _socket = socket;
      var sockListen = socket.listen((data) {
        for (var el in data) {
          _dataStream.add(el);
        }
      });
      sockListen.onDone(() => destroy());
      sockListen.onError((err) => destroy());

      _byteQueue = StreamQueue<int>(_dataStream.stream);
      _readPacketsEvents().listen((event) => _eventStream.add(event));
      _eventStream.add(ConnectedEvent());

      _connected = true;

      var connReq = OutgoingPacket();
      connReq.addString(info.password);
      connReq.send(socket);
    }).catchError((err) {
      destroy();
    });
  }

  Future<int> _readU8() async => _byteQueue.next;

  Future<int> _readU16() async => (await _readU8()) * 256 + (await _readU8());

  Future<String> _readString() async {
    var len = await _readU16();
    return utf8.decode(await _byteQueue.take(len));
  }

  Stream<AlinesEvent> eventStream() => _eventStream.stream;

  Stream<AlinesEvent> _readPacketsEvents() async* {
    while (true) {
      try {
        var packetId = await _readU8();
        if (packetId == 0) {
          yield DisconnectEvent(await _readString());
          destroy();
        } else if (packetId == 1) {
          var flags = await _readU8();
          var entryCount = await _readU16();
          var title = await _readString();
          var entries = <String>[];
          for (var i = 0; i < entryCount; i++) {
            entries.add(await _readString());
          }
          yield OpenMenuEvent(Menu(title, entries, flags));
        } else {
          throw "Invalid incoming packet id";
        }
      } catch (err) {
        break;
      }
    }
  }

  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    if (_connected) {
      _socket.destroy();
      _dataStream.close();
      _connected = false;
    }
    _eventStream.add(DestroyedEvent());
    _eventStream.close();
  }

  void closeMenu() {
    var packet = OutgoingPacket();
    packet.addU8(0);
    packet.send(_socket);
  }

  void selectSingleEntry(int id) {
    var packet = OutgoingPacket();
    packet.addU8(1);
    packet.addU16(id);
    packet.send(_socket);
  }

  void selectMultipleEntries(List<int> ids) {
    var packet = OutgoingPacket();
    packet.addU8(2);
    packet.addU16(ids.length);
    for (var id in ids) {
      packet.addU16(id);
    }
    packet.send(_socket);
  }

  void customEntry(String entry) {
    var packet = OutgoingPacket();
    packet.addU8(3);
    packet.addString(entry);
    packet.send(_socket);
  }
}
