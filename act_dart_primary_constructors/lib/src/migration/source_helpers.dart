part of '../migration.dart';

String _sourceFor(String source, AstNode node) {
  return source.substring(node.offset, node.end);
}

String _lineIndentation(String source, int offset) {
  var start = offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }
  return source.substring(start, offset);
}
