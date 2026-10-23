import { parse } from "svelte/compiler"
import ts from "typescript"
import { inspectOrdering } from "./ordering.ts"
import { spacingPositions } from "./spacing.ts"
import { bindingNames, scriptUnits, syntaxDiagnostics, walkSvelte, walkTs } from "./syntax.ts"

export interface FrontendIssue {
  path: string
  line: number
  column: number
  rule: string
  message: string
}

export interface FrontendOptions {
  customElements?: readonly string[]
  embeds?: readonly string[]
}

const platformConstructors = new Set(["ResizeObserver", "IntersectionObserver", "MutationObserver"])

const exemptClass = (node: ts.ClassLikeDeclaration, file: string, options: FrontendOptions) => {
  if (file.endsWith(".test.ts") && node.name && platformConstructors.has(node.name.text)) {
    return true
  }
  return Boolean(
    options.customElements?.includes(file) &&
      node.heritageClauses?.some(
        (clause) =>
          clause.token === ts.SyntaxKind.ExtendsKeyword &&
          clause.types.some((type) => type.expression.getText() === "HTMLElement"),
      ),
  )
}

const moduleSpecifier = (node: ts.Node) => {
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

const inlineFunction = (value: Record<string, unknown>) =>
  value.type === "ArrowFunctionExpression" || value.type === "FunctionExpression"

const parameterName = (node: ts.Node): string | undefined => {
  if (
    ts.isBinaryExpression(node) &&
    node.operatorToken.kind >= ts.SyntaxKind.FirstAssignment &&
    node.operatorToken.kind <= ts.SyntaxKind.LastAssignment &&
    ts.isIdentifier(node.left)
  ) {
    return node.left.text
  }
  if (
    (ts.isPrefixUnaryExpression(node) || ts.isPostfixUnaryExpression(node)) &&
    [ts.SyntaxKind.PlusPlusToken, ts.SyntaxKind.MinusMinusToken].includes(node.operator) &&
    ts.isIdentifier(node.operand)
  ) {
    return node.operand.text
  }
  return undefined
}

const reassignsParameter = (node: ts.Node) => {
  const name = parameterName(node)
  if (!name) {
    return false
  }
  let scope = node.parent
  while (scope) {
    if (
      ts.isBlock(scope) &&
      scope.statements.some(
        (statement) =>
          ts.isVariableStatement(statement) &&
          statement.declarationList.declarations.some((declaration) =>
            bindingNames(declaration.name).includes(name),
          ),
      )
    ) {
      return false
    }
    if (
      ts.isFunctionLike(scope) &&
      scope.parameters.some((parameter) => bindingNames(parameter.name).includes(name))
    ) {
      return true
    }
    scope = scope.parent
  }
  return false
}

const isInClass = (node: ts.Node) => {
  let scope = node.parent
  while (scope) {
    if (ts.isClassLike(scope)) {
      return true
    }
    scope = scope.parent
  }
  return false
}

const valueRule = (node: ts.Node): [string, string] | undefined => {
  if (node.kind === ts.SyntaxKind.ThisKeyword && !isInClass(node)) {
    return ["no-this", "Pass framework context explicitly to an arrow callback."]
  }
  if (reassignsParameter(node)) {
    return ["no-parameter-assign", "Keep parameters immutable; use a local value."]
  }
  if (
    ts.isArrowFunction(node) &&
    node.type?.kind === ts.SyntaxKind.NeverKeyword &&
    ts.isVariableDeclaration(node.parent) &&
    !node.parent.type
  ) {
    return ["never-function-type", "Give a never-returning const an explicit function type."]
  }
  return undefined
}

const containsConditional = (node: ts.Node): boolean => {
  if (ts.isFunctionLike(node)) {
    return false
  }
  if (ts.isConditionalExpression(node)) {
    return true
  }
  return ts.forEachChild(node, containsConditional) ?? false
}

const syntaxRule = (
  node: ts.Node,
  file: string,
  options: FrontendOptions,
): [string, string] | undefined => {
  if (ts.isClassLike(node) && !exemptClass(node, file, options)) {
    return ["no-classes", "Use a create… factory with closure state and a plain object."]
  }
  if (
    ts.isFunctionDeclaration(node) ||
    ts.isFunctionExpression(node) ||
    (ts.isMethodDeclaration(node) && ts.isObjectLiteralExpression(node.parent))
  ) {
    return ["arrow-functions", "Use a const arrow function or an arrow property."]
  }
  if (ts.isArrowFunction(node) && ts.isExportAssignment(node.parent)) {
    return ["const-functions", "Name the default-exported arrow with a const binding."]
  }
  if (
    ts.isVariableDeclaration(node) &&
    node.initializer &&
    ts.isArrowFunction(node.initializer) &&
    ts.isVariableDeclarationList(node.parent) &&
    !(node.parent.flags & ts.NodeFlags.Const)
  ) {
    return ["const-functions", "Declare arrow functions with const."]
  }
  if (
    ts.isConditionalExpression(node) &&
    [node.condition, node.whenTrue, node.whenFalse].some(containsConditional)
  ) {
    return ["no-nested-ternary", "Use a named function or explicit branches."]
  }
  return undefined
}

export const inspectFrontendSource = (
  file: string,
  source: string,
  options: FrontendOptions = {},
): FrontendIssue[] => {
  const issues: FrontendIssue[] = []

  const report = (position: number, rule: string, message: string) => {
    const before = source.slice(0, position)
    const line = before.split("\n").length
    issues.push({ path: file, line, column: position - before.lastIndexOf("\n"), rule, message })
  }

  for (const { ast, offset } of scriptUnits(file, source)) {
    const diagnostics = syntaxDiagnostics(ast)
    if (diagnostics.length) {
      diagnostics.forEach((diagnostic) => {
        report(
          offset + diagnostic.start,
          "parse",
          ts.flattenDiagnosticMessageText(diagnostic.messageText, " "),
        )
      })
      continue
    }
    walkTs(ast, (node) => {
      const position = offset + node.getStart(ast)
      const violation = syntaxRule(node, file, options) ?? valueRule(node)
      if (violation) {
        report(position, ...violation)
      }
      const specifier = moduleSpecifier(node)
      if (specifier && file.startsWith("assets/")) {
        if (specifier.startsWith(".")) {
          report(position, "alias-imports", "Use a $lib or $seeds alias for internal imports.")
        }
        if (specifier.endsWith(".js")) {
          report(position, "ts-imports", "Import TypeScript source with its .ts extension.")
        }
      }
    })
    inspectOrdering(ast).forEach(({ position, name }) => {
      report(offset + position, "load-order", `${name} is evaluated before its const declaration.`)
    })
  }
  spacingPositions(file, source).forEach((position) => {
    report(position, "spacing", "Separate functions, types, imports and lifecycle/test groups.")
  })
  if (!file.endsWith(".svelte")) {
    return issues
  }
  if (
    !file.endsWith(".stories.svelte") &&
    source.split("\n").length - Number(source.endsWith("\n")) > 300
  ) {
    report(0, "component-size", "Keep a non-story Svelte component within 300 lines.")
  }
  const ast = parse(source, { modern: true })
  walkSvelte(ast.fragment, (node) => {
    if (
      node.type === "RegularElement" &&
      ["button", "input", "select", "textarea"].includes(String(node.name)) &&
      !file.startsWith("assets/primitives/") &&
      !options.embeds?.includes(file)
    ) {
      report(
        Number(node.start),
        "primitive-controls",
        "Compose a primitive instead of a raw control.",
      )
    }
    if (
      node.type === "OnDirective" &&
      node.expression &&
      inlineFunction(node.expression as Record<string, unknown>)
    ) {
      report(Number(node.start), "named-handlers", "Pass a named event handler by reference.")
    }
    if (
      node.type !== "Attribute" ||
      typeof node.name !== "string" ||
      !/^on[a-zA-Z]/.test(node.name)
    ) {
      return
    }
    const values = Array.isArray(node.value) ? node.value : [node.value]
    values.forEach((value) => {
      const expression = (value as Record<string, unknown>)?.expression as
        | Record<string, unknown>
        | undefined
      if (expression && inlineFunction(expression)) {
        report(
          Number(node.start),
          "named-handlers",
          "Pass a named event/callback handler by reference.",
        )
      }
    })
  })
  return issues
}
