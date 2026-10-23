import ts from "typescript"
import { bindingNames, statementLists } from "./syntax.ts"

interface Binding {
  name: string
  node: ts.VariableDeclaration
  index: number
  scope: Scope
}

interface Scope {
  parent?: Scope
  bindings: Map<string, Binding | null>
  statements: readonly ts.Statement[]
}

export interface OrderingIssue {
  position: number
  name: string
}

const createScope = (statements: readonly ts.Statement[], parent?: Scope): Scope => {
  const scope: Scope = { parent, statements, bindings: new Map() }
  statements.forEach((statement, index) => {
    if (!ts.isVariableStatement(statement)) {
      return
    }
    statement.declarationList.declarations.forEach((node) => {
      for (const name of bindingNames(node.name)) {
        scope.bindings.set(name, { name, node, index, scope })
      }
    })
  })
  return scope
}

const resolveBinding = (name: string, scope?: Scope): Binding | undefined => {
  if (!scope) {
    return undefined
  }
  if (scope.bindings.has(name)) {
    return scope.bindings.get(name) ?? undefined
  }
  return resolveBinding(name, scope.parent)
}

const unwrap = (expression: ts.Expression): ts.Expression => {
  if (
    ts.isParenthesizedExpression(expression) ||
    ts.isAsExpression(expression) ||
    ts.isSatisfiesExpression(expression) ||
    ts.isNonNullExpression(expression)
  ) {
    return unwrap(expression.expression)
  }
  return expression
}

interface ArrowCall {
  arrow: ts.ArrowFunction
  scope: Scope
}

const calledArrow = (
  expression: ts.Expression,
  scope: Scope,
  seen = new Set<Binding>(),
): ArrowCall | undefined => {
  const value = unwrap(expression)
  if (ts.isArrowFunction(value)) {
    return { arrow: value, scope }
  }
  if (ts.isIdentifier(value)) {
    const binding = resolveBinding(value.text, scope)
    if (!binding || seen.has(binding) || !binding.node.initializer) {
      return undefined
    }
    seen.add(binding)
    return calledArrow(binding.node.initializer, binding.scope, seen)
  }
  if (ts.isPropertyAccessExpression(value) && ts.isIdentifier(value.expression)) {
    const binding = resolveBinding(value.expression.text, scope)
    const initializer = binding?.node.initializer
    if (binding && initializer && ts.isObjectLiteralExpression(initializer)) {
      const property = initializer.properties.find(
        (item) => ts.isPropertyAssignment(item) && item.name.getText() === value.name.text,
      )
      if (property && ts.isPropertyAssignment(property)) {
        return calledArrow(property.initializer, binding.scope, seen)
      }
    }
  }
  return undefined
}

const locallyBound = (name: string, scope?: Scope): boolean => {
  if (!scope) {
    return false
  }
  return scope.bindings.has(name) || locallyBound(name, scope.parent)
}

const deferredCall = (expression: ts.Expression, scope: Scope) => {
  if (
    calledArrow(expression, scope) ||
    (ts.isIdentifier(expression) && locallyBound(expression.text, scope))
  ) {
    return false
  }
  if (
    expression.getText() === "$derived.by" ||
    /^(test|it|describe)\.(skip|only|todo|each)$/.test(expression.getText())
  ) {
    return true
  }
  let name = ""
  if (ts.isIdentifier(expression)) {
    name = expression.text
  } else if (ts.isPropertyAccessExpression(expression)) {
    name = expression.name.text
  }
  return new Set([
    "$effect",
    "onMount",
    "onDestroy",
    "setTimeout",
    "setInterval",
    "queueMicrotask",
    "requestAnimationFrame",
    "addEventListener",
    "handleEvent",
    "then",
    "catch",
    "finally",
    "test",
    "it",
    "describe",
    "before",
    "after",
    "beforeEach",
    "afterEach",
    "beforeAll",
    "afterAll",
  ]).has(name)
}

const isReference = (node: ts.Identifier) => {
  const parent = node.parent
  return !(
    (ts.isPropertyAccessExpression(parent) && parent.name === node) ||
    (ts.isPropertyAssignment(parent) && parent.name === node) ||
    (ts.isVariableDeclaration(parent) && parent.name === node) ||
    (ts.isParameter(parent) && parent.name === node) ||
    ts.isImportSpecifier(parent) ||
    ts.isImportClause(parent) ||
    ts.isBindingElement(parent) ||
    ts.isTypeNode(parent) ||
    ts.isLabeledStatement(parent)
  )
}

export const inspectOrdering = (ast: ts.SourceFile): OrderingIssue[] => {
  const issues = new Map<string, OrderingIssue>()
  const active = new Set<ts.ArrowFunction>()
  const origins = new Map<Scope, number>()

  const reference = (node: ts.Identifier, scope: Scope) => {
    if (!isReference(node)) {
      return
    }
    const binding = resolveBinding(node.text, scope)
    const initializer = binding?.node.initializer
    const index = binding && origins.get(binding.scope)
    if (
      binding &&
      initializer &&
      calledArrow(node, scope) &&
      index !== undefined &&
      binding.index > index
    ) {
      issues.set(`${node.pos}:${binding.name}`, {
        position: node.getStart(ast),
        name: binding.name,
      })
    }
  }

  const evaluateStatements = (statements: readonly ts.Statement[], parent?: Scope) => {
    const scope = createScope(statements, parent)
    statements.forEach((statement, index) => {
      origins.set(scope, index)
      evaluate(statement, scope)
    })
    origins.delete(scope)
  }

  const invoke = (arrow: ts.ArrowFunction, scope: Scope) => {
    if (active.has(arrow)) {
      return
    }
    active.add(arrow)
    const frame = createScope([], scope)
    arrow.parameters.forEach((parameter) => {
      bindingNames(parameter.name).forEach((name) => {
        frame.bindings.set(name, null)
      })
      if (parameter.initializer) {
        evaluate(parameter.initializer, frame)
      }
    })
    if (ts.isBlock(arrow.body)) {
      evaluateStatements(arrow.body.statements, frame)
    } else {
      evaluate(arrow.body, frame)
    }
    active.delete(arrow)
  }

  const evaluateCall = (node: ts.CallExpression, scope: Scope) => {
    evaluate(node.expression, scope)
    const deferred = deferredCall(node.expression, scope)
    node.arguments.forEach((argument) => {
      const arrow = calledArrow(argument, scope)
      if (arrow && !deferred) {
        invoke(arrow.arrow, arrow.scope)
      } else {
        evaluate(argument, scope)
      }
    })
    const arrow = calledArrow(node.expression, scope)
    if (arrow) {
      invoke(arrow.arrow, arrow.scope)
    }
  }

  const evaluate = (node: ts.Node, scope: Scope): void => {
    if (
      ts.isTypeNode(node) ||
      ts.isFunctionLike(node) ||
      ts.isClassLike(node) ||
      ts.isImportDeclaration(node) ||
      ts.isExportDeclaration(node)
    ) {
      return
    }
    if (ts.isIdentifier(node)) {
      reference(node, scope)
      return
    }
    if (ts.isCallExpression(node)) {
      evaluateCall(node, scope)
      return
    }
    if (ts.isBlock(node)) {
      evaluateStatements(node.statements, scope)
      return
    }
    ts.forEachChild(node, (child) => evaluate(child, scope))
  }

  statementLists(ast).forEach((statements) => {
    evaluateStatements(statements)
  })
  return [...issues.values()]
}
