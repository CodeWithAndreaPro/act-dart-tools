part of 'primary_constructors.dart';

String _sourceFor(String source, AstNode node) {
  return source.substring(node.offset, node.end);
}

SourceRange _rangeFor(AstNode node) {
  return SourceRange(offset: node.offset, length: node.length);
}

SourceRange? _blockClassBodyContentRange(ClassBody body) {
  if (body is! BlockClassBody) {
    return null;
  }
  return SourceRange.fromStartEnd(
    start: body.leftBracket.end,
    end: body.rightBracket.offset,
  );
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
