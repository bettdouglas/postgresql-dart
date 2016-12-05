import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/src/exceptions.dart';
import 'package:postgres/src/query.dart';


abstract class ServerMessage {
  void readBytes(Uint8List bytes);
}

class ErrorResponseMessage implements ServerMessage {
  PostgreSQLException generatedException;
  List<ErrorField> fields = [new ErrorField()];

  void readBytes(Uint8List bytes) {
    var lastByteRemovedList =
        new Uint8List.view(bytes.buffer, bytes.offsetInBytes, bytes.length - 1);

    lastByteRemovedList.forEach((byte) {
      if (byte != 0) {
        fields.last.add(byte);
        return;
      }

      fields.add(new ErrorField());
    });

    generatedException = new PostgreSQLException.fromFields(fields);
  }

  String toString() => generatedException.toString();
}

class AuthenticationMessage implements ServerMessage {
  static const int KindOK = 0;
  static const int KindKerberosV5 = 2;
  static const int KindClearTextPassword = 3;
  static const int KindMD5Password = 5;
  static const int KindSCMCredential = 6;
  static const int KindGSS = 7;
  static const int KindGSSContinue = 8;
  static const int KindSSPI = 9;

  int type;

  List<int> salt;

  void readBytes(Uint8List bytes) {
    var view = new ByteData.view(bytes.buffer, bytes.offsetInBytes);
    type = view.getUint32(0);

    if (type == KindMD5Password) {
      salt = new List<int>(4);
      for (var i = 0; i < 4; i++) {
        salt[i] = view.getUint8(4 + i);
      }
    }
  }

  String toString() => "Authentication: $type";
}

class ParameterStatusMessage extends ServerMessage {
  String name;
  String value;

  void readBytes(Uint8List bytes) {
    name = UTF8.decode(bytes.sublist(0, bytes.indexOf(0)));
    value =
        UTF8.decode(bytes.sublist(bytes.indexOf(0) + 1, bytes.lastIndexOf(0)));
  }

  String toString() => "Parameter Message: $name $value";
}

class ReadyForQueryMessage extends ServerMessage {
  static const String StateIdle = "I";
  static const String StateTransaction = "T";
  static const String StateTransactionError = "E";

  String state;

  void readBytes(Uint8List bytes) {
    state = UTF8.decode(bytes);
  }

  String toString() => "Ready Message: $state";
}

class BackendKeyMessage extends ServerMessage {
  int processID;
  int secretKey;

  void readBytes(Uint8List bytes) {
    var view = new ByteData.view(bytes.buffer, bytes.offsetInBytes);
    processID = view.getUint32(0);
    secretKey = view.getUint32(4);
  }

  String toString() => "Backend Key Message: $processID $secretKey";
}

class RowDescriptionMessage extends ServerMessage {
  List<FieldDescription> fieldDescriptions;

  void readBytes(Uint8List bytes) {
    var view = new ByteData.view(bytes.buffer, bytes.offsetInBytes);
    var offset = 0;
    var fieldCount = view.getInt16(offset);
    offset += 2;

    fieldDescriptions = <FieldDescription>[];
    for (var i = 0; i < fieldCount; i++) {
      var rowDesc = new FieldDescription();
      offset = rowDesc.parse(view, offset);
      fieldDescriptions.add(rowDesc);
    }
  }

  String toString() => "RowDescription Message: $fieldDescriptions";
}

class DataRowMessage extends ServerMessage {
  List<ByteData> values = [];

  void readBytes(Uint8List bytes) {
    var view = new ByteData.view(bytes.buffer, bytes.offsetInBytes);
    var offset = 0;
    var fieldCount = view.getInt16(offset);
    offset += 2;

    for (var i = 0; i < fieldCount; i++) {
      var dataSize = view.getInt32(offset);
      offset += 4;

      if (dataSize == 0) {
        values.add(new ByteData(0));
      } else if (dataSize == -1) {
        values.add(null);
      } else {
        var rawBytes = new ByteData.view(
            bytes.buffer, bytes.offsetInBytes + offset, dataSize);
        values.add(rawBytes);
        offset += dataSize;
      }
    }
  }

  String toString() => "Data Row Message: ${values}";
}

class CommandCompleteMessage extends ServerMessage {
  int rowsAffected;

  static RegExp identifierExpression = new RegExp(r"[A-Z ]*");

  void readBytes(Uint8List bytes) {
    var str = UTF8.decode(bytes.sublist(0, bytes.length - 1));

    var match = identifierExpression.firstMatch(str);
    if (match.end < str.length) {
      rowsAffected = int.parse(str.split(" ").last);
    } else {
      rowsAffected = 0;
    }
  }

  String toString() => "Command Complete Message: $rowsAffected";
}

class ParseCompleteMessage extends ServerMessage {
  void readBytes(Uint8List bytes) {}

  String toString() => "Parse Complete Message";
}

class BindCompleteMessage extends ServerMessage {
  void readBytes(Uint8List bytes) {}

  String toString() => "Bind Complete Message";
}

class ParameterDescriptionMessage extends ServerMessage {
  List<int> parameterTypeIDs;

  void readBytes(Uint8List bytes) {
    var view = new ByteData.view(bytes.buffer, bytes.offsetInBytes);

    var offset = 0;
    var count = view.getUint16(0);
    offset += 2;

    parameterTypeIDs = [];
    for (var i = 0; i < count; i++) {
      var v = view.getUint32(offset);
      offset += 4;
      parameterTypeIDs.add(v);
    }
  }

  String toString() => "Parameter Description Message: $parameterTypeIDs";
}

class NoDataMessage extends ServerMessage {
  void readBytes(Uint8List bytes) {}

  String toString() => "No Data Message";
}

class UnknownMessage extends ServerMessage {
  Uint8List bytes;
  int code;

  void readBytes(Uint8List bytes) {
    this.bytes = bytes;
  }

  String toString() => "Unknown message: $code $bytes";
}
