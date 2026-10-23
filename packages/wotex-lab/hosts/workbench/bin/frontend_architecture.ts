import { parse } from "svelte/compiler"
import ts from "typescript"

export interface FrontendIssue {
  line: number
  message: string
}

const scripts = (file: string, source: string) => {
  if (!file.endsWith(".svelte")) {
    return [{ source, offset: 0 }]
  }
  return [...source.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map((match) => ({
    source: match[1],
    offset: (match.index ?? 0) + match[0].indexOf(">") + 1,
  }))
}

const isFunction = (node: ts.Node) =>
  (ts.isVariableStatement(node) &&
    node.declarationList.declarations.some(
      (value) => value.initializer && ts.isArrowFunction(value.initializer),
    )) ||
  (ts.isPropertyAssignment(node) && ts.isArrowFunction(node.initializer))

const siblingNodes = (node: ts.Node): readonly ts.Node[] => {
  if (ts.isSourceFile(node) || ts.isBlock(node)) {
    return node.statements
  }
  if (ts.isObjectLiteralExpression(node)) {
    return node.properties
  }
  return []
}

const moduleSpecifier = (node: ts.Node): string | undefined => {
  if (
    (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) &&
    node.moduleSpecifier &&
    ts.isStringLiteral(node.moduleSpecifier)
  ) {
    return node.moduleSpecifier.text
  }
  if (
    ts.isCallExpression(node) &&
    node.expression.kind === ts.SyntaxKind.ImportKeyword &&
    node.arguments[0] &&
    ts.isStringLiteral(node.arguments[0])
  ) {
    return node.arguments[0].text
  }
  if (
    ts.isImportTypeNode(node) &&
    ts.isLiteralTypeNode(node.argument) &&
    ts.isStringLiteral(node.argument.literal)
  ) {
    return node.argument.literal.text
  }
  return undefined
}

const syntaxIssue = (node: ts.Node) => {
  if (ts.isClassDeclaration(node) || ts.isClassExpression(node)) {
    return "Use a function or closure factory instead of a class"
  }
  if (
    ts.isFunctionDeclaration(node) ||
    ts.isFunctionExpression(node) ||
    ts.isMethodDeclaration(node) ||
    ts.isGetAccessorDeclaration(node) ||
    ts.isSetAccessorDeclaration(node)
  ) {
    return "Use a named arrow function"
  }
  return undefined
}

const spacingPositions = (file: string, source: string) => {
  const positions = new Set<number>()
  for (const script of scripts(file, source)) {
    const ast = ts.createSourceFile(
      file,
      script.source,
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.TS,
    )

    const visit = (node: ts.Node) => {
      const siblings = siblingNodes(node)
      for (let index = 1; index < siblings.length; index += 1) {
        const previous = siblings[index - 1]
        const next = siblings[index]
        if (!isFunction(previous) && !isFunction(next)) {
          continue
        }
        const gap = script.source.slice(previous.end, next.getStart(ast))
        if (gap.includes("\n") && !/\n\s*\n/.test(gap)) {
          positions.add(script.offset + script.source.indexOf("\n", previous.end) + 1)
        }
      }
      ts.forEachChild(node, visit)
    }

    visit(ast)
  }
  return [...positions].sort((left, right) => right - left)
}

export const formatFunctionSpacing = (file: string, source: string) =>
  spacingPositions(file, source).reduce(
    (text, position) => `${text.slice(0, position)}\n${text.slice(position)}`,
    source,
  )

const walkObjects = (value: unknown, visit: (node: Record<string, unknown>) => void) => {
  if (!value || typeof value !== "object") {
    return
  }
  if (Array.isArray(value)) {
    value.forEach((item) => {
      walkObjects(item, visit)
    })
    return
  }
  const node = value as Record<string, unknown>
  visit(node)
  Object.values(node).forEach((item) => {
    walkObjects(item, visit)
  })
}

const delegatedEvent = (expression: Record<string, unknown>) => {
  if (expression.type !== "ArrowFunctionExpression") {
    return expression.type !== "FunctionExpression"
  }
  const raw = expression.body as Record<string, unknown>
  const body = (raw.type === "ChainExpression" ? raw.expression : raw) as Record<string, unknown>
  return (
    body.type === "CallExpression" ||
    (body.type === "UnaryExpression" &&
      body.operator === "void" &&
      (body.argument as Record<string, unknown>).type === "CallExpression")
  )
}

export const inspectFrontendSource = (file: string, source: string): FrontendIssue[] => {
  const issues: FrontendIssue[] = []

  const report = (position: number, message: string) =>
    issues.push({ line: source.slice(0, position).split("\n").length, message })

  for (const script of scripts(file, source)) {
    const ast = ts.createSourceFile(
      file,
      script.source,
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.TS,
    )

    const visit = (node: ts.Node) => {
      const issue = syntaxIssue(node)
      if (issue) {
        report(script.offset + node.getStart(ast), issue)
      }
      const specifier = moduleSpecifier(node)
      if (specifier && file.startsWith("assets/")) {
        if (specifier.startsWith(".")) {
          report(
            script.offset + node.getStart(ast),
            "Use a $lib or $seeds alias for internal imports",
          )
        }
        if (specifier.endsWith(".js")) {
          report(
            script.offset + node.getStart(ast),
            "Import TypeScript source with its .ts extension",
          )
        }
      }
      ts.forEachChild(node, visit)
    }

    visit(ast)
  }
  for (const position of spacingPositions(file, source)) {
    report(position, "Separate named functions and methods with a blank line")
  }
  if (file.endsWith(".svelte")) {
    const component = parse(source, { modern: true })
    walkObjects(component.fragment, (node) => {
      if (
        node.type !== "Attribute" ||
        typeof node.name !== "string" ||
        !/^on[a-z]+$/.test(node.name)
      ) {
        return
      }
      const value = node.value as Record<string, unknown>
      const expression = value?.expression as Record<string, unknown> | undefined
      if (expression && !delegatedEvent(expression)) {
        report(Number(node.start), "Delegate event behavior to a named function")
      }
    })
  }
  return issues
}
