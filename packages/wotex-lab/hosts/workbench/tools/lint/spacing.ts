import ts from "typescript"
import { scriptUnits, walkTs } from "./syntax.ts"

const typeDeclaration = (node: ts.Node) =>
  ts.isTypeAliasDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isEnumDeclaration(node)

const namedFunction = (node: ts.Node) =>
  ts.isFunctionDeclaration(node) ||
  (ts.isVariableStatement(node) &&
    node.declarationList.declarations.some(
      (declaration) => declaration.initializer && ts.isArrowFunction(declaration.initializer),
    ))

const functionMember = (node: ts.Node) =>
  ts.isGetAccessorDeclaration(node) ||
  ts.isSetAccessorDeclaration(node) ||
  ts.isMethodDeclaration(node) ||
  (ts.isPropertyAssignment(node) && ts.isArrowFunction(node.initializer))

const groupCall = (node: ts.Node) =>
  ts.isExpressionStatement(node) &&
  ts.isCallExpression(node.expression) &&
  /^(test|it|describe|before|after|beforeEach|afterEach|beforeAll|afterAll|onMount|onDestroy|\$effect)(\.|$)/.test(
    node.expression.expression.getText(),
  )

const siblings = (node: ts.Node): readonly ts.Node[] => {
  if (ts.isSourceFile(node) || ts.isBlock(node) || ts.isModuleBlock(node)) {
    return node.statements
  }
  if (ts.isObjectLiteralExpression(node)) {
    return node.properties
  }
  return []
}

const needsSpace = (previous: ts.Node, next: ts.Node, ast: ts.SourceFile) => {
  if (ts.isImportDeclaration(previous) && ts.isImportDeclaration(next)) {
    return false
  }
  if (ts.isObjectLiteralExpression(previous.parent)) {
    const multiline = (node: ts.Node) => node.getText(ast).includes("\n")

    return (
      (functionMember(previous) || functionMember(next)) && (multiline(previous) || multiline(next))
    )
  }
  return (
    ts.isImportDeclaration(previous) ||
    typeDeclaration(previous) ||
    typeDeclaration(next) ||
    namedFunction(previous) ||
    namedFunction(next) ||
    groupCall(previous) ||
    groupCall(next)
  )
}

export const spacingPositions = (file: string, source: string) => {
  const positions = new Set<number>()
  for (const { ast, offset } of scriptUnits(file, source)) {
    walkTs(ast, (node) => {
      const list = siblings(node)
      for (let index = 1; index < list.length; index += 1) {
        const previous = list[index - 1]
        const next = list[index]
        if (!needsSpace(previous, next, ast)) {
          continue
        }
        const gap = ast.text.slice(previous.end, next.getStart(ast))
        if (!/\n[\t ]*\n/.test(gap)) {
          const newline = gap.indexOf("\n")
          positions.add(offset + previous.end + (newline < 0 ? 0 : newline + 1))
        }
      }
    })
  }
  return [...positions].sort((left, right) => right - left)
}

export const formatSpacing = (file: string, source: string) =>
  spacingPositions(file, source).reduce(
    (text, position) => `${text.slice(0, position)}\n${text.slice(position)}`,
    source,
  )
