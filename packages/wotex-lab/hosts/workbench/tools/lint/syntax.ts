import { parse } from "svelte/compiler"
import ts from "typescript"

export interface ScriptUnit {
  ast: ts.SourceFile
  offset: number
}

export const bindingNames = (name: ts.BindingName): string[] => {
  if (ts.isIdentifier(name)) {
    return [name.text]
  }
  return name.elements.flatMap((element) =>
    ts.isOmittedExpression(element) ? [] : bindingNames(element.name),
  )
}

// TypeScript 6.0.3 attaches parser diagnostics here; SourceFile's public type omits the field.
export const syntaxDiagnostics = (ast: ts.SourceFile) =>
  (ast as ts.SourceFile & { parseDiagnostics: readonly ts.DiagnosticWithLocation[] })
    .parseDiagnostics

export const scriptUnits = (file: string, source: string): ScriptUnit[] => {
  const scripts = file.endsWith(".svelte")
    ? [parse(source, { modern: true }).instance, parse(source, { modern: true }).module]
        .filter((script) => script !== null && script !== undefined)
        .map((script) => ({
          text: source.slice(
            (script.content as unknown as { start: number }).start,
            (script.content as unknown as { end: number }).end,
          ),
          offset: (script.content as unknown as { start: number }).start,
        }))
    : [{ text: source, offset: 0 }]
  return scripts.map(({ text, offset }) => ({
    ast: ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS),
    offset,
  }))
}

export const walkTs = (node: ts.Node, visit: (node: ts.Node) => void) => {
  visit(node)
  ts.forEachChild(node, (child) => walkTs(child, visit))
}

export const walkSvelte = (value: unknown, visit: (node: Record<string, unknown>) => void) => {
  if (!value || typeof value !== "object") {
    return
  }
  if (Array.isArray(value)) {
    value.forEach((child) => {
      walkSvelte(child, visit)
    })
    return
  }
  const node = value as Record<string, unknown>
  visit(node)
  Object.values(node).forEach((child) => {
    walkSvelte(child, visit)
  })
}

export const statementLists = (ast: ts.SourceFile) => {
  const result: (readonly ts.Statement[])[] = []
  walkTs(ast, (node) => {
    if (ts.isSourceFile(node) || ts.isBlock(node) || ts.isModuleBlock(node)) {
      result.push(node.statements)
    }
    if (ts.isCaseBlock(node)) {
      node.clauses.forEach((clause) => {
        result.push(clause.statements)
      })
    }
  })
  return result
}
