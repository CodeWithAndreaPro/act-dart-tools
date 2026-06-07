part of '../migration.dart';

String _sourceFor(String source, AstNode node) {
  return source.substring(node.offset, node.end);
}

SourceRange _rangeFor(AstNode node) {
  return SourceRange(offset: node.offset, length: node.length);
}

_DeclarationBodyInfo _classBodyInfo(ClassDeclaration declaration) {
  return _DeclarationBodyInfo(
    members: declaration.body.members,
    bodyEnd: declaration.body.end,
  );
}

_DeclarationBodyInfo _enumBodyInfo(EnumDeclaration declaration) {
  return _DeclarationBodyInfo(
    members: declaration.body.members,
    bodyEnd: declaration.body.end,
  );
}

String _lineIndentation(String source, int offset) {
  var start = offset;
  while (start > 0 && source.codeUnitAt(start - 1) != 10) {
    start--;
  }
  return source.substring(start, offset);
}
